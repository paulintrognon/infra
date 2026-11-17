# mariage

A wedding organisation app (private repo `paulintrognon/mariage`): a React Router server and its PostgreSQL database, at https://mariage.paulintrognon.fr, behind HTTP basic auth.

| File | What |
|---|---|
| `postgres-statefulset.yaml`, `postgres-service.yaml` | The database and its disk |
| `deployment.yaml`, `service.yaml` | The app; an init container migrates the database first |
| `middlewares.yaml`, `ingress.yaml` | HTTPS, basic auth |
| `backup-cronjob.yaml` | Nightly dump of the database to object storage |

## Secrets created by hand

This repo is public, so these Secrets are never committed: they are created once with `kubectl`, and Argo CD leaves them alone (it only manages what is in git). Keep their values in a password manager: losing the cluster means recreating them.

**`mariage-db`**: the database password, and the URL the app connects with.

```bash
PW=$(openssl rand -hex 32)
kubectl create secret generic mariage-db \
  --from-literal=POSTGRES_PASSWORD="$PW" \
  --from-literal=DATABASE_URL="postgres://mariage:$PW@mariage-postgres:5432/mariage"
```

Postgres reads `POSTGRES_PASSWORD` only when it creates an empty database. Changing it later means `ALTER USER mariage PASSWORD '…'` in the database too.

**`mariage-basic-auth`**: one htpasswd line per person (bcrypt).

```bash
# htpasswd comes with apache2-utils, or: docker run --rm httpd:2.4-alpine htpasswd …
# Once per person: prints the password (note it), then the line to keep.
P=$(openssl rand -base64 24); echo "$P"; htpasswd -nbB <login> "$P"
kubectl create secret generic mariage-basic-auth --from-file=users=<file with the lines>
```

**`ghcr-pull`**: lets the cluster pull the private image. Needs a GitHub *classic* token with only the `read:packages` scope (fine-grained tokens don't work with ghcr.io).

```bash
kubectl create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=paulintrognon --docker-password=<token>
```

**`mariage-backup`**: object storage keys for `backup-cronjob.yaml`.

Scaleway grants a key its rights over a whole project, not over one bucket. So the `paulin-mariage-backups` bucket sits alone in its own project, `mariage`: if the key leaks from the cluster, it reaches these dumps and nothing else. The key belongs to an IAM application `mariage-backup` (a technical account, no console access), whose policy is scoped to the `mariage` project with `ObjectStorageObjectsRead`, `ObjectStorageObjectsWrite` and `ObjectStorageBucketsRead`. No delete right: dumps are never pruned (see `backup-cronjob.yaml`), so a stolen key can't delete them (it could still overwrite one; bucket versioning would close that gap). The key's preferred project is `mariage`: Scaleway's S3 API looks buckets up there.

```bash
kubectl create secret generic mariage-backup \
  --from-literal=AWS_ACCESS_KEY_ID=… --from-literal=AWS_SECRET_ACCESS_KEY=…
```

### Rotating the backup key

Scaleway API keys in this organisation expire after one year at most. An expired key doesn't break the app; it silently stops the backups: every night the upload is refused and the Job fails, and nothing alerts. So rotate the key a couple of weeks before it expires (keep a calendar reminder):

1. Scaleway console → IAM → Applications → `mariage-backup` → API keys → generate a new key (Object Storage, preferred project `mariage`, longest validity allowed). Store it in the password manager.
2. Replace the Secret in place (`create --dry-run | apply` overwrites an existing Secret, which `create` alone refuses to do):

   ```bash
   kubectl create secret generic mariage-backup \
     --from-literal=AWS_ACCESS_KEY_ID=… --from-literal=AWS_SECRET_ACCESS_KEY=… \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

3. Run a backup now with the new key, and check it ends `Complete` and lists today's dump:

   ```bash
   kubectl create job --from=cronjob/mariage-backup mariage-backup-manual
   kubectl wait --for=condition=complete job/mariage-backup-manual --timeout=5m
   kubectl logs job/mariage-backup-manual -c upload
   kubectl delete job mariage-backup-manual
   ```

4. Only then, delete the old key in the Scaleway console, and set the next reminder.

Checking that backups still run, at any time: `kubectl get cronjob mariage-backup` (column `LAST SUCCESS`).

## Restoring a backup

Restores in place, into the running database: the dump replaces every table, the migrations' bookkeeping included. The same steps work on a fresh, empty disk, where the app has already re-run the migrations and the couple's seed rows.

1. Download the dump: Scaleway console → project `mariage` → Object Storage → `paulin-mariage-backups` → the file you want → Download. The newest is the last in the list (names are UTC timestamps).
2. Load it with the `pg_restore` of the database's own pod (same version, nothing to install):

   ```bash
   kubectl exec -i mariage-postgres-0 -- \
     pg_restore --clean --if-exists --no-owner --single-transaction --exit-on-error \
     -U mariage -d mariage < mariage-<timestamp>.dump
   ```

   - `--clean --if-exists`: drop each table before recreating it, so the restore doesn't clash with what is there.
   - `--single-transaction --exit-on-error`: all or nothing. On any error the database is left exactly as it was, never half-restored.

3. Reload the app in the browser: it reads the database on every page, no restart needed.

## Deploying a new version

The app's CI pushes `ghcr.io/paulintrognon/mariage:sha-<commit>` on every push to its `main`. Deploying is changing that tag in `deployment.yaml` (twice: the init container and the app container must run the same version) and merging. The pod is stopped, the migrations run, then the new version starts: a few seconds of downtime.
