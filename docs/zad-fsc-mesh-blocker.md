# Platform-blokkade — FSC interne mTLS-mesh vs. ZAD één-poort-model

> **Samenvatting voor het RIG/ZAD-platformteam:** een ZAD-component kan precies één inbound-poort
> publiceren, waardoor er per pod maar één cluster-interne Service ontstaat. FSC-componenten
> (`manager`, `controller`) luisteren op meerdere mTLS-poorten met verschillende cert-ketens die
> cluster-intern bereikbaar moeten zijn. Daardoor kan de FSC-provider-peer `magazijn-a` op ZAD niet
> volledig functioneren. We vragen om een manier om **meerdere poorten per component** (of een extra
> cluster-interne Service per component) te exposen.

- **Peer / project:** `magazijn-a` (Organisatie A), ZAD-project `mpfoa-e01`, deployment `test`,
  namespace `rig-prd-mpfoa-e01` (OpenShift).
- **Software:** OpenFSC `v1.43.7` (RINIS), images `manager`/`controller`/`inway`/`txlog-api`.
- **Datum bevinding:** 2026-07-10.

## De blokkade

FSC scheidt per component het **externe/group-verkeer** (mesh, group-PKI) van de **interne API's**
(component-tot-component, internal-PKI) over **verschillende poorten met verschillende
cert-ketens**. ZAD publiceert per component slechts één poort → één ClusterIP-Service op precies
die poort. De overige containerpoorten hebben geen Service, geen cluster-DNS en zijn alleen via het
(instabiele) pod-IP bereikbaar. Gevolg: alle interne mTLS-edges tussen manager, controller en inway
zijn cluster-intern onbereikbaar.

Concreet symptoom: de controller logt bij het openen van de directory-pagina

```text
could not retrieve Peers from Manager ... Get "https://mgzmgr-test-mpfoa-e01.<domein>:443/v1/peers":
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

De controller verifieert met de **internal-CA** maar landt via `:443` op het **externe/group**-
endpoint (poort 8443, group-cert) — omdat de manager-internal-poort (9443) geen bereikbaar adres
heeft en het internal-verkeer daarom (verkeerd) over de `:443`-ingress is geconfigureerd.

## Bewijs

1. **ZAD-API accepteert één poort.** `AddComponentRequest` in het OpenAPI-schema
   (`https://operations-manager.rig.prd1.gn2.quattro.rijksapps.nl/openapi.json`) heeft één veld
   `port` ("Inbound port (omit for background workers)") — géén `ports`-array, geen extra
   expose-/networking-veld.
2. **Gemeten Services (via kubelet service-link env-vars in een netshoot-job; default-SA mag geen
   `list services`, 403):** elke component heeft exact één Service-poort =

   | Service | ClusterIP | Enige poort | FSC-betekenis |
   |---------|-----------|-------------|---------------|
   | `test-mgzmgr` | 172.30.235.238 | 8443 | extern/group (mist 9443, 9444) |
   | `test-mgzctl` | 172.30.37.30 | 8080 | UI (mist 9443, 9444) |
   | `test-mgzinway` | 172.30.196.65 | 80 | data-plane |
   | `test-mgztxlog` | 172.30.43.63 | 8443 | txlog (werkt: enige poort = listener) |

## FSC-poort/cert-model (uit de werkende lokale compose)

| Component | Poort | Rol | Cert-keten |
|-----------|-------|-----|------------|
| manager | 8443 | `LISTEN_ADDRESS_EXTERNAL` (mesh) | group |
| manager | 9443 | `LISTEN_ADDRESS_INTERNAL` (controller→manager) | internal |
| manager | 9444 | `LISTEN_ADDRESS_INTERNAL_UNAUTHENTICATED` (inway→manager) | internal |
| controller | 8080 | `LISTEN_ADDRESS_UI` | — |
| controller | 9443 | `LISTEN_ADDRESS_REGISTRATION_API` (inway/manager→controller) | internal |
| controller | 9444 | `LISTEN_ADDRESS_ADMINISTRATION_API` (onboarding→controller) | internal |

### Interne edges die op ZAD onbereikbaar zijn

| Van → naar | Poort | Status op ZAD |
|------------|-------|---------------|
| controller → manager | manager 9443 | ❌ geen Service |
| manager → controller | controller 9443 | ❌ geen Service |
| inway → controller | controller 9443 | ❌ geen Service |
| inway → manager | manager 9444 | ❌ geen Service |
| manager/inway → txlog | txlog 8443 | ✅ (toevallig: enige poort) |
| manager/inway ↔ directory & peers | 8443 via `:443`-ingress | ✅ (SNI-passthrough) |

## Wat we van het platform nodig hebben

Eén van (voorkeur bovenaan):

1. **Meerdere inbound-poorten per component** in de v2-API (`ports`-array) → elke poort krijgt een
   ClusterIP-Service. Dan exposen we manager `8443+9443+9444` en controller `8080+9443+9444`.
2. **Een extra (cluster-interne, niet-gepubliceerde) Service per component** voor opgegeven
   containerpoorten — mesh-verkeer blijft op de `:443`-ingress, interne poorten worden alleen
   cluster-intern bereikbaar.
3. **Een headless Service / stabiele pod-DNS** zodat een sidecar-/proxy-component de interne poorten
   kan bereiken.

De externe mesh (manager + inway op `:443`, SNI-passthrough) werkt al en hoeft niet te wijzigen.

## Waarom de gebruikelijke workarounds hier niet gelden

- **Adressen re-pointen in de deploy** helpt niet: de interne poort bestáát niet cluster-intern.
- **Losse k8s-Services aanmaken** kan niet met onze rechten (default-SA: 403 op `list services`;
  we hebben alleen de ZAD-UI: image + command + één poort).
- **Co-locatie tot loopback** (meerdere FSC-binaries in één component) lost het niet op: manager en
  inway hebben elk een eigen publieke mesh-hostnaam nodig, en één component = één Route/hostnaam.
- **Tweede FSC-instance op dezelfde DB** puur om een interne poort te exposen is niet
  ondersteund/veilig (dubbele announce, txlog, leader-aannames).

## Verificatie (2026-07-10) — announce werkt, publiceren geblokkeerd

Getest vanaf een host met egress + de lokale group-cert, tegen de gepubliceerde mesh-endpoint
`https://mgzmgr-test-mpfoa-e01.<domein>:443`:

- **Announce (AC-3) ✅** — `GET /v1/peers` geeft `HTTP 200` met onze peer
  `00000001003214345000` (naam `magazijn-a`, correcte `manager_address` op `:443`) naast de
  Directory-peer. De manager meldt zich dus succesvol aan; de externe mesh + onze group-cert werken.
- **Publiceren (AC-4) ❌** — de management-flow "maak+onderteken contract" zit op de manager's
  **interne** `:9443` (waar `publish-service.sh` naartoe POST) en die is onbereikbaar. De **externe**
  `/v1/contracts` is de **inter-manager sync**-endpoint: een `POST` met de `publish-service.sh`-body
  gaf `HTTP 400 Header parameter fsc-manager-address is required`, en mét die header `HTTP 500 could
  not map grants from REST to application / unexpected end of JSON input` — de endpoint verwacht een
  **al-ondertekend** contract in het peer-uitwisselingsformaat, niet een create-request. Zelf het
  contract client-side hashen+ondertekenen (SHA3-512 + de manager-contract-key) zou het interne
  manager-protocol namaken: te fragiel/onhaalbaar. Na de pogingen is `GET /v1/contracts` nog leeg en
  `berichtenmagazijn` staat niet in de catalogus (niets gepubliceerd, geen neveneffect).

**Slotsom:** richting 2 (publiceren buiten de interne mesh om) is **geen werkbare workaround** — het
signeren van een servicePublication-contract vereist onvermijdelijk de management-API op de
onbereikbare interne poort. Announce lukt (aparte, uitgaande boot-flow), maar publiceren niet.
Alleen de platform-fix (deze aanvraag) deblokkeert AC-4.

## Referenties

- Ontwerp + eerdere bevindingen: `docs/design.md` (open-punt "Interne-mTLS poort/routering op ZAD").
- Werkende referentie-topologie: `deploy/local/docker-compose.yaml`.
- ZAD-rollout: `deploy/zad/upsert-peer.sh`, `deploy/zad/README.md`.
