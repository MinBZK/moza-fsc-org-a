# Organisatie A — FSC provider-peer

Een **FSC provider-peer** voor Organisatie A die de dienst `berichtenmagazijn` (magazijn-a)
aanbiedt en zich aansluit op de FSC-federatie van [`moza-fsc-testnet`](https://github.com/MinBZK/moza-fsc-testnet)
(repo A — de directory + group-CA). De peer bestaat uit de standaard OpenFSC-componenten
**manager + controller + inway + txlog** met een eigen managed Postgres, co-located met de
achterliggende magazijn-app.

Gemodelleerd naar repo A's `example-provider`; deze repo bevat uitsluitend FSC-infra (PKI +
deploy), niet de magazijn-applicatie zelf.

> **Niet voor productie.** Test-PKI en test-federatie (`moza-fbs-test`). Sleutels/certs horen
> **niet** in git — zie `.gitignore`.

## Identiteit

| Parameter | Waarde |
|-----------|--------|
| Peer-naam | `magazijn-a` |
| Peer-OIN (= Peer ID) | `00000001003214345000` |
| Group ID | `moza-fbs-test` |
| Directory-OIN | `00000000000000000010` |
| Dienst in de directory | `berichtenmagazijn` |
| FSC-images (pin) | `v1.43.7` (manager/controller/inway/txlog) |

> De organisatie heet functioneel "Organisatie A"; de technische identifiers gebruiken nog
> `magazijn-a` (peer) en `berichtenmagazijn` (dienst). Hernoemen kan later — let dan op de OIN in
> de `csr.json`'s en de hostnamen in de SAN's.

## Structuur

| Pad | Rol |
|-----|-----|
| `pki/` | Test-PKI: group- + internal-certs per endpoint (cfssl). Zie `pki/README.md`. |
| `deploy/local/` | Lokale docker-compose-proof: directory + peer + SNI-router + smokes. |
| `deploy/zad/` | ZAD-rollout (Operations Manager v2-API): `upsert-peer.sh` + cert-/verificatie-runbooks. |
| `.github/workflows/zad-deploy-peer.yml` | Deployt de peer naar ZAD op elke PR-push. |
| `docs/design.md` | Ontwerp + ZAD-bevindingen (oorspronkelijk uit de berichtenbox-repo). |

## Quickstart

### 1. PKI — group-CA van het testnet + certs uitgeven

De group-leaf moet ketenen naar **fsc-testnet's** group-root. Zet daarom fsc-testnet's
`ca/root.pem` + `ca/intermediate.pem` (+ keys) in `pki/ca/` en draai **niet** `init-ca.sh`
(dat maakt een verse, vreemde CA — alleen goed voor de geïsoleerde lokale proof):

```bash
cd pki
# (voor de lokale proof: ./init-ca.sh   — eigen CA)
./issue.sh          # group- + internal-cert per endpoint
./gen-crl.sh        # lege CRL
./verify.sh         # acceptatie-asserts (exit 0 = groen)
./zad-bundle.sh magazijn-a   # upload-klare set in pki/zad-upload/magazijn-a/
```

### 2. Lokale compose-proof

```bash
cd deploy/local
cp .env.example .env      # vul PKI_DIR + HOST_UID/GID
docker compose up -d
./run-smokes.sh           # announce + publish + discover
```

### 3. ZAD

Zie `deploy/zad/README.md`. Kort:

- Eigen ZAD-project `mpfoa-e2w`, deployment `test`, eigen API-key (secret `ZAD_API_KEY_FSCORGA`).
- `upsert-peer.sh` beheert deployment + componenten + images.
- Cert-attachments + "Publicatie op het web" (passthrough) zijn **UI-only** — zie `cert-manifest.md`.

## Belangrijke ZAD-lessen (zie `docs/design.md`)

- **Component-env is UI-beheerd.** De v2-API zet env/aliases alleen bij component-**creatie**;
  een re-POST werkt een bestaande component niet bij. De workflow is betrouwbaar voor
  images/refs; runtime-env zet/wijzig je in de UI.
- **`$DEPLOYMENT_NAME`-substitutie vermijden.** De deployment is vast, dus `upsert-peer.sh` lost
  alle inter-component-hostnamen concreet op in `env_vars`; alleen de managed-Postgres-DSN
  (`$DATABASE_*`) leunt op ZAD-substitutie (in `aliases`).
- **txlog is verplicht.** Een niet-directory manager faalt hard op een lege `TX_LOG_API_ADDRESS`.
- **Cert-mount-valkuilen.** Internal-pad = internal-cert (getekend door de per-peer internal-CA);
  group-pad = group-cert **inclusief** aangehechte intermediate. Verwissel ze niet.

## Licentie

[EUPL v1.2](LICENSE).
