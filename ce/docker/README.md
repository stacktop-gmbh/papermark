# CE Local Docker Setup

This folder provides a self-contained local setup for CE development:

- starts local Postgres + app via Docker Compose
- creates a Prisma shadow database
- writes/updates a managed block in root `.env.local` and `.env`

## Files

- `docker-compose.local.yml` - local Postgres + app services
- `Dockerfile.app` - app base image (`node:24-alpine`) with OpenSSL preinstalled
- `start-app.sh` - deterministic app startup (`npm ci` on signature change, with fallback to `npm install` if lockfile is out of sync)
- `.env.local.example` - config template for docker/env generation
- `up-local.sh` - start DB + app + sync root `.env.local`/`.env`
- `down-local.sh` - stop services (`--volumes` to wipe data)

## Quick Start

1. Start DB + app and generate app env values:

```bash
./ce/docker/up-local.sh
```

2. Open app:

```bash
http://localhost:3003
```

3. Watch app logs:

```bash
docker compose --env-file ./ce/docker/.env.local -f ./ce/docker/docker-compose.local.yml logs -f app
```

## Stop / Reset

Stop containers:

```bash
./ce/docker/down-local.sh
```

Stop and delete DB volume:

```bash
./ce/docker/down-local.sh --volumes
```

## Notes

- `up-local.sh` keeps your own `.env.local`/`.env` content and only manages the block:
  - `# >>> CE DOCKER LOCAL START`
  - `# <<< CE DOCKER LOCAL END`
- Default local ports are Postgres `55432` and web `3003`.
- Default DB image is `postgres:18-alpine` (configurable via `POSTGRES_IMAGE` in `ce/docker/.env.local`).
- Default app image is `node:24-alpine` (configurable via `APP_IMAGE` in `ce/docker/.env.local`).
- App image is built locally from `Dockerfile.app` and installs OpenSSL.
- `up-local.sh` refreshes upstream images (`docker compose pull`) and rebuilds app image with `--pull` on each run.
- `up-local.sh` waits for app readiness using `curl` before reporting success (default timeout: 180s).
- Readiness timing is configurable via `APP_READY_TIMEOUT_SECONDS` and `APP_READY_CHECK_INTERVAL_SECONDS`.
- If lockfile drift is detected, app startup falls back from `npm ci` to `npm install`; this can update `package-lock.json`.
- If you switch Postgres major versions, run `./ce/docker/down-local.sh --volumes` once to reinitialize local data.
- Docker volumes are used for Postgres data, app `node_modules`, Next.js build cache (`.next`), and npm cache.
- Edit `ce/docker/.env.local` if you need custom images, credentials, or ports.
