# Cert-attachments op ZAD — magazijn-a-peer

> Draaiboek voor de mens: de cert-attachments mounten. Uit te voeren ná `pki/issue.sh` (zie
> `pki/README.md`) en rond `upsert-peer.sh apply`.

## Waarom UI-only

De ZAD v2 Operations Manager API dekt deployment + componenten (image, env_vars, aliases,
services) maar **geen bijlagen** — net als repo A's directory-deploy
(`deploy/zad/upsert-directory.sh`, zie de header-comment daar). Cert-mounts op
`/etc/fsc/...`-paden gaan dus via de ZAD-UI, per component, als losse attachment-bestanden
(geen `combined.pem` nodig — zie `pki/zad-bundle.sh`, modus 2/passthrough).

## Volgorde

0. **Group-CA plaatsen (NIET `init-ca.sh`).** Voor de échte directory moet de group-leaf ketenen
   naar fsc-testnet's group-root. Zet fsc-testnet's `ca/root.pem` + `ca/intermediate.pem` (+ keys)
   in `pki/ca/` — draai `init-ca.sh` **niet** (dat maakt een verse, vreemde CA). De
   INTERNAL-CA blijft wél lokaal/self-signed (die maakt `issue.sh` per-peer aan).
1. `pki/issue.sh` (vereist `cfssl`) — genereert `pki/out/magazijn-a/*` (group,
   getekend door fsc-testnet's intermediate) en `pki/internal/magazijn-a/*` (internal).
   **Let op (multi-poort-fix, 2026-07-13):** de internal-cert-SAN's bevatten nu ook de
   cluster-interne Service-DNS (`test-<comp>` + `test-<comp>.rig-prd-mpfoa-e01.svc.cluster.local`),
   waarnaar het interne mTLS-verkeer verbindt. Draaide je `issue.sh` vóór deze wijziging, geef de
   certs dan opnieuw uit met `issue.sh -f` (anders faalt de hostnaamverificatie op `test-mgzmgr:9443`
   enz.) en upload de verse set opnieuw.
2. `pki/zad-bundle.sh magazijn-a` (hangt af van stap 1) — verzamelt de
   upload-klare set in `pki/zad-upload/magazijn-a/` met een eigen `MANIFEST.md`
   (bestand → pod-pad → `TLS_*`-env-var, zie dat script voor de exacte `env_for()`-mapping).
3. Per component (`mgzmgr`, `mgzctl`, `mgzinway`) in de ZAD-UI: bijlage toevoegen op het
   `/etc/fsc/...`-pad uit de tabellen hieronder, met de bestandsinhoud uit stap 2's
   upload-set. De paden zijn identiek aan de `TLS_*`-waarden die `upsert-peer.sh` al als
   `env_vars`/`aliases` naar de component stuurt — de attachment moet dus exact op dat pad
   gemount worden, anders faalt de container-boot met een ontbrekend-bestand-fout.

## mgzmgr (manager)

| Bijlage-pad (`/etc/fsc/...`) | Bronbestand (`pki/...`) | Env-var op mgzmgr |
|-------------------------------|-------------------------------------------|--------------------|
| `ca/root.pem` | `ca/root.pem` | `TLS_GROUP_ROOT_CERT` |
| `out/magazijn-a/manager/cert.pem` | `out/magazijn-a/manager/cert.pem` | `TLS_GROUP_CERT`, `TLS_GROUP_TOKEN_CERT`, `TLS_GROUP_CONTRACT_CERT` |
| `out/magazijn-a/manager/key.pem` | `out/magazijn-a/manager/key.pem` | `TLS_GROUP_KEY`, `TLS_GROUP_TOKEN_KEY`, `TLS_GROUP_CONTRACT_KEY` |
| `internal/magazijn-a/ca/root.pem` | `internal/magazijn-a/ca/root.pem` | `TLS_ROOT_CERT`, `TLS_INTERNAL_UNAUTHENTICATED_ROOT_CERT` |
| `internal/magazijn-a/manager/cert.pem` | `internal/magazijn-a/manager/cert.pem` | `TLS_CERT`, `TLS_INTERNAL_UNAUTHENTICATED_CERT` |
| `internal/magazijn-a/manager/key.pem` | `internal/magazijn-a/manager/key.pem` | `TLS_KEY`, `TLS_INTERNAL_UNAUTHENTICATED_KEY` |

## mgzctl (controller)

| Bijlage-pad (`/etc/fsc/...`) | Bronbestand (`pki/...`) | Env-var op mgzctl |
|-------------------------------|-------------------------------------------|--------------------|
| `internal/magazijn-a/ca/root.pem` | `internal/magazijn-a/ca/root.pem` | `TLS_ROOT_CERT` |
| `internal/magazijn-a/controller/cert.pem` | `internal/magazijn-a/controller/cert.pem` | `TLS_CERT` |
| `internal/magazijn-a/controller/key.pem` | `internal/magazijn-a/controller/key.pem` | `TLS_KEY` |

De controller heeft geen group-cert nodig (hij spreekt geen mesh-verkeer met andere peers, alleen
de eigen manager op de internal-PKI) — vandaar geen `out/magazijn-a/controller/*`-rij.

## mgzinway (inway)

| Bijlage-pad (`/etc/fsc/...`) | Bronbestand (`pki/...`) | Env-var op mgzinway |
|-------------------------------|-------------------------------------------|--------------------|
| `ca/root.pem` | `ca/root.pem` | `TLS_GROUP_ROOT_CERT` |
| `out/magazijn-a/inway/cert.pem` | `out/magazijn-a/inway/cert.pem` | `TLS_GROUP_CERT` |
| `out/magazijn-a/inway/key.pem` | `out/magazijn-a/inway/key.pem` | `TLS_GROUP_KEY` |
| `internal/magazijn-a/ca/root.pem` | `internal/magazijn-a/ca/root.pem` | `TLS_ROOT_CERT` |
| `internal/magazijn-a/inway/cert.pem` | `internal/magazijn-a/inway/cert.pem` | `TLS_CERT` |
| `internal/magazijn-a/inway/key.pem` | `internal/magazijn-a/inway/key.pem` | `TLS_KEY` |

## mgztxlog (txlog-api)

txlog spreekt uitsluitend mTLS op de INTERNAL-PKI (geen group-cert — group-agnostische opslag),
net als in de lokale compose.

| Bijlage-pad (`/etc/fsc/...`) | Bronbestand (`pki/...`) | Env-var op mgztxlog |
|-------------------------------|-------------------------------------------|--------------------|
| `internal/magazijn-a/ca/root.pem` | `internal/magazijn-a/ca/root.pem` | `TLS_ROOT_CERT` |
| `internal/magazijn-a/txlog/cert.pem` | `internal/magazijn-a/txlog/cert.pem` | `TLS_CERT` |
| `internal/magazijn-a/txlog/key.pem` | `internal/magazijn-a/txlog/key.pem` | `TLS_KEY` |

## mgzpg (self-hosted Postgres) — géén cert, wél een init-script-attachment

Sinds 2026-07-15 draait de peer een eigen postgres-component `mgzpg` (self-hosted) i.p.v. ZAD's
managed Postgres, zodat we de schema-init zelf beheren (zie `docs/design.md` + `upsert-peer.sh`). Geen
TLS-attachments (intra-cluster plaintext op `:5432`, `sslmode=disable`), maar wél één attachment: het
init-script dat de 3 schema's aanmaakt.

| Bijlage-pad (in de mgzpg-container) | Bronbestand (repo) | Werking |
|-------------------------------------|--------------------|---------|
| `/docker-entrypoint-initdb.d/10-schemas.sql` | `deploy/zad/postgres-init.sql` | postgres draait dit éénmalig bij lege PGDATA → `CREATE SCHEMA manager/controller/txlog` |

Verder geen bijlagen op mgzpg. Het wachtwoord komt uit `ZAD_PG_PASSWORD` (env bij `apply`, niet in git);
`POSTGRES_USER`/`POSTGRES_DB`/`PGDATA` staan als component-env.

**Persistentie:** zonder gekoppeld persistent volume is de DB ephemeral — bij een nieuwe pod draait het
init-script opnieuw en zijn de tabellen leeg (manager migreert vanzelf via de wrapper; controller/txlog
moeten dan opnieuw migreren). Voor een blijvende peer: een persistent volume op `PGDATA` koppelen.

**Schema-namen moeten sporen** met `ZAD_MGR_SCHEMA`/`ZAD_CTL_SCHEMA`/`ZAD_TXLOG_SCHEMA` in
`upsert-peer.sh` (defaults manager/controller/txlog). Wijzig je de één, wijzig dan de ander mee.

## Controller- en txlog-migraties draaien (geen wrapper)

De manager migreert bij boot via de `manager-migrate`-wrapper. De controller en txlog draaien op hun
stock-image en hebben **geen** migratiestap — draai die eenmalig (bv. een ZAD-job of exec in de pod)
tegen `mgzpg`, mét dezelfde `search_path` als serve, anders landen de tabellen in het verkeerde schema:

```
/usr/local/bin/controller migrate up \
  --postgres-dsn "postgres://<user>:<pass>@test-mgzpg:5432/fsc?sslmode=disable&search_path=controller"
/usr/local/bin/txlog-api  migrate up \
  --postgres-dsn "postgres://<user>:<pass>@test-mgzpg:5432/fsc?sslmode=disable&search_path=txlog"
```

Omdat elk component nu zijn eigen schema (dus eigen `schema_migrations`) heeft, draaien deze migraties
vers vanaf versie 0 en ontstaan de ontbrekende tabellen (o.a. `controller.services`).

## Na het mounten

Herstart (of laat ZAD herstarten na attachment-wijziging) elk component en controleer de boot-log
op een TLS-laadfout — een fout pad of een verwisselde group/internal-cert faalt hard bij startup
("no such file", of een handshake-fout tegen de verkeerde CA). Ga daarna verder met
`verify-zad.md`.

## Bestaande componenten migreren naar de nieuwe env/poorten (multi-poort-fix)

ZAD past `env_vars`/`ports` alléén bij component-**creatie** toe, niet bij een re-POST op een
bestaande component (zie `design.md`). Bestaan de componenten al met de oude (`:443`-)config, dan
zijn er twee routes om de nieuwe interne adressen + poorten door te voeren:

- **Poorten los bijwerken via de API** (env blijft ongemoeid): `PATCH
  /api/v2/projects/mpfoa-e01/components/<comp>` met body `{"ports":[…]}` (mgzmgr `[8443,9443,9444]`,
  mgzctl `[8080,9443,9444]`). Zet daarnaast de interne adressen (`MANAGER_ADDRESS_INTERNAL` etc.)
  in de **UI**, want env is UI-beheerd op een bestaande component. Cert-attachments blijven behouden.
- **Component verwijderen + opnieuw aanmaken** (via `upsert-peer.sh apply`, die env+ports in één
  keer zet): dan raak je de cert-attachments kwijt en moet je ze **opnieuw mounten** (deze tabellen).

Na het her-uitgeven van de certs (`issue.sh -f`, want de SAN's zijn gewijzigd) is opnieuw uploaden
sowieso nodig — dus in de praktijk is verwijderen + opnieuw aanmaken + herattachen de schoonste weg.
