# Verificatie ná apply — magazijn-a-peer op ZAD

> Draaiboek: wat een mens ná een geslaagde `upsert-peer.sh apply` + cert-attachments (zie
> `cert-manifest.md`) nog controleert.

## Volgorde

1. `upsert-peer.sh apply` gedraaid → deployment + componenten bestaan in project `mpfoa-e01`.
2. Cert-attachments gemount (zie `cert-manifest.md`) + "Publicatie op het web"
   (passthrough-TLS, modus 2) op mgzmgr/mgzinway ingesteld in de ZAD-UI.
3. Componenten herstart en boot-logs foutloos (zie `cert-manifest.md`, laatste sectie).

## (a) Announce — magazijn-OIN vindbaar in de directory

Verwacht gedrag (analoog aan `deploy/local/smoke-announce.sh`, maar tegen de
ZAD-directory-DB i.p.v. de lokale compose-postgres):

```bash
# Via de mgzmgr-mesh-host (:443), met de group-cert als client-cert:
curl -sS --cert <group-cert> --key <group-key> --cacert <group-root> \
  "https://<dirmgr-host-op-ZAD>/v1/peers" | jq '.[] | select(.id == "00000001003214345000")'
```

Verwacht: één entry met `id: "00000001003214345000"` en een `manager_address` die eindigt op
`:443` en het mgzmgr-hostpatroon (`mgzmgr-<deployment>-mpfoa-e01.<base-domain>`) bevat.

Alternatief (UI): log in op de directory-UI (repo A's `dirui`-component) en zoek de peer op OIN.

## (b) `berichtenmagazijn` publiceren op de ZAD-controller

`:443`-variant van `deploy/local/publish-service.sh`: dezelfde
create-service + servicePublication-contract-flow, maar tegen de mgzctl Administration-API op
`:443` (mesh) i.p.v. de lokale toolbox-container op de internal-PKI. Twee routes:

- **Script**: kopieer `publish-service.sh` se logica, vervang `$CONTROLLER`/`$MANAGER` door de
  ZAD mesh-hosts (`https://mgzctl-<deployment>-mpfoa-e01.<base-domain>:443` resp. mgzmgr) en het
  cert/key/CA door de group-cert-attachments (niet de internal-cert — de mesh-call loopt over de
  group-PKI, zie `cert-manifest.md`).
- **UI**: via de mgzctl-beheer-UI (`LISTEN_ADDRESS_UI`, `AUTHN_TYPE=none`) een dienst aanmaken
  met naam `berichtenmagazijn`, `endpoint_url` = de waarde uit `upsert-peer.sh`'s
  `MAGAZIJNA_UPSTREAM_URL` (de ingress-URL van de app cross-deployment, bv.
  `https://magazijna-test-mpfm-w3h.<base-domain>`) en `inway_address` = de geregistreerde
  mgzinway `SELF_ADDRESS`.

Verwacht: de contract-respons bevat `content_hash` (manager signt) en de directory (
`AUTO_SIGN_GRANTS=servicePublication,delegatedServicePublication` op de directory-manager, buiten
deze bundel) accepteert automatisch.

## (c) Discover — dienst vindbaar

Analoog aan `deploy/local/smoke-discover.sh`, tegen de ZAD-directory-DB of
via de directory-UI: `berichtenmagazijn` moet als dienst van OIN `00000001003214345000` in de
catalogus staan.

## Acceptatiecriteria — afvinklijst

- [ ] Peer (echte OIN) draait op ZAD: manager + controller + inway + txlog + DB (project-isolatie)
- [ ] Peer heeft een geldige group-cert (getekend onder fsc-testnet's group-CA)
- [ ] Peer meldt zich aan bij de directory (announce)
- [ ] `berichtenmagazijn` gepubliceerd + vindbaar in de directory

Elk vinkje vereist een mens met ZAD-toegang, gegenereerde certs en een draaiende peer.
