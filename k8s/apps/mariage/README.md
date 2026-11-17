# mariage

A wedding organisation app (private repo `paulintrognon/mariage`): a React Router server and its PostgreSQL database, at https://mariage.paulintrognon.fr, behind HTTP basic auth.

| File | What |
|---|---|
| `postgres-statefulset.yaml`, `postgres-service.yaml` | The database and its disk |
| `deployment.yaml`, `service.yaml` | The app; an init container migrates the database first |
| `middlewares.yaml`, `ingress.yaml` | HTTPS, rate limit, basic auth |

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
htpasswd -nbB <login> "$(openssl rand -base64 24)"   # once per person; note each password
kubectl create secret generic mariage-basic-auth --from-file=users=<file with the lines>
```

**`ghcr-pull`**: lets the cluster pull the private image. Needs a GitHub *classic* token with only the `read:packages` scope (fine-grained tokens don't work with ghcr.io).

```bash
kubectl create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=paulintrognon --docker-password=<token>
```

## Deploying a new version

The app's CI pushes `ghcr.io/paulintrognon/mariage:sha-<commit>` on every push to its `main`. Deploying is changing that tag in `deployment.yaml` (both the init container and the app container) and merging. The pod is stopped, the migrations run, then the new version starts: a few seconds of downtime.
