#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
DOCKER_ENV_FILE="$SCRIPT_DIR/.env.local"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.local.yml"
ROOT_ENV_LOCAL_FILE="$ROOT_DIR/.env.local"
ROOT_ENV_FILE="$ROOT_DIR/.env"

compose() {
  docker compose --env-file "$DOCKER_ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

if [ ! -f "$DOCKER_ENV_FILE" ]; then
  cp "$SCRIPT_DIR/.env.local.example" "$DOCKER_ENV_FILE"
  echo "Created $DOCKER_ENV_FILE from template."
fi

compose_environment="$(compose config --environment)"

get_compose_env() {
  local key="$1"
  local default_value="$2"
  local missing_sentinel="__MISSING__CODEX__"
  local value

  value="$(
    printf '%s\n' "$compose_environment" |
      awk -F= -v k="$key" -v missing="$missing_sentinel" '
        $1 == k {
          print substr($0, length(k) + 2)
          found = 1
          exit
        }
        END {
          if (!found) {
            print missing
          }
        }
      '
  )"

  if [ "$value" = "$missing_sentinel" ]; then
    printf '%s\n' "$default_value"
  else
    printf '%s\n' "$value"
  fi
}

POSTGRES_USER="$(get_compose_env POSTGRES_USER "papermark")"
POSTGRES_PASSWORD="$(get_compose_env POSTGRES_PASSWORD "papermark")"
POSTGRES_DB="$(get_compose_env POSTGRES_DB "papermark")"
POSTGRES_SHADOW_DB="$(get_compose_env POSTGRES_SHADOW_DB "papermark_shadow")"
POSTGRES_HOST="$(get_compose_env POSTGRES_HOST "localhost")"
POSTGRES_PORT="$(get_compose_env POSTGRES_PORT "55432")"
WEB_PORT="$(get_compose_env WEB_PORT "3003")"
APP_READY_TIMEOUT_SECONDS="$(get_compose_env APP_READY_TIMEOUT_SECONDS "180")"
APP_READY_CHECK_INTERVAL_SECONDS="$(get_compose_env APP_READY_CHECK_INTERVAL_SECONDS "2")"
NEXTAUTH_URL="$(get_compose_env NEXTAUTH_URL "http://localhost:$WEB_PORT")"
NEXTAUTH_SECRET="$(get_compose_env NEXTAUTH_SECRET "local-dev-secret-change-me")"
APP_BASE_HOST="$(get_compose_env APP_BASE_HOST "localhost")"
WEBHOOK_BASE_HOST="$(get_compose_env WEBHOOK_BASE_HOST "localhost")"

if ! [[ "$APP_READY_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [ "$APP_READY_TIMEOUT_SECONDS" -le 0 ]; then
  echo "APP_READY_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 1
fi
if ! [[ "$APP_READY_CHECK_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [ "$APP_READY_CHECK_INTERVAL_SECONDS" -le 0 ]; then
  echo "APP_READY_CHECK_INTERVAL_SECONDS must be a positive integer." >&2
  exit 1
fi

compose pull postgres
compose build --pull app
compose up -d postgres

ready="0"
for _ in $(seq 1 30); do
  if compose exec -T postgres \
    pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
    ready="1"
    break
  fi
  sleep 2
done

if [ "$ready" != "1" ]; then
  echo "Postgres did not become ready in time."
  exit 1
fi

db_exists="$(compose exec -T postgres \
  psql -U "$POSTGRES_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_SHADOW_DB';" || true)"
if [ "$db_exists" != "1" ]; then
  compose exec -T postgres \
    psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$POSTGRES_SHADOW_DB\";" >/dev/null
fi

managed_block="$(cat <<EOT
# >>> CE DOCKER LOCAL START
POSTGRES_PRISMA_URL=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB?schema=public
POSTGRES_PRISMA_URL_NON_POOLING=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB?schema=public
POSTGRES_PRISMA_SHADOW_URL=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_SHADOW_DB?schema=public

NEXTAUTH_SECRET=$NEXTAUTH_SECRET
NEXTAUTH_URL=$NEXTAUTH_URL
NEXT_PUBLIC_BASE_URL=$NEXTAUTH_URL
NEXT_PUBLIC_MARKETING_URL=$NEXTAUTH_URL
PORT=$WEB_PORT

NEXT_PUBLIC_APP_BASE_HOST=$APP_BASE_HOST
NEXT_PUBLIC_WEBHOOK_BASE_HOST=$WEBHOOK_BASE_HOST

NEXT_PUBLIC_UPLOAD_TRANSPORT=vercel
NEXT_PRIVATE_UPLOAD_DISTRIBUTION_HOST=localhost
NEXT_PRIVATE_DOCUMENT_PASSWORD_KEY=local-document-password-secret
NEXT_PRIVATE_VERIFICATION_SECRET=local-verification-secret

SLACK_CLIENT_ID=local
SLACK_CLIENT_SECRET=local
HANKO_API_KEY=local
NEXT_PUBLIC_HANKO_TENANT_ID=local
# <<< CE DOCKER LOCAL END
EOT
)"

update_env_file() {
  local target_file="$1"
  local tmp_file
  tmp_file="$(mktemp)"

  if [ -f "$target_file" ]; then
    perl -0777 -pe 's/# >>> CE DOCKER LOCAL START.*?# <<< CE DOCKER LOCAL END\n?//s' "$target_file" > "$tmp_file"
  else
    : > "$tmp_file"
  fi

  {
    cat "$tmp_file"
    if [ -s "$tmp_file" ]; then
      printf "\n"
    fi
    printf "%s\n" "$managed_block"
  } > "$target_file"

  rm -f "$tmp_file"
}

update_env_file "$ROOT_ENV_LOCAL_FILE"
update_env_file "$ROOT_ENV_FILE"

compose up -d app

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required for app readiness checks." >&2
  exit 1
fi

app_ready="0"
max_attempts="$(((APP_READY_TIMEOUT_SECONDS + APP_READY_CHECK_INTERVAL_SECONDS - 1) / APP_READY_CHECK_INTERVAL_SECONDS))"

for _ in $(seq 1 "$max_attempts"); do
  if curl --silent --fail --output /dev/null "http://localhost:$WEB_PORT"; then
    app_ready="1"
    break
  fi
  sleep "$APP_READY_CHECK_INTERVAL_SECONDS"
done

if [ "$app_ready" != "1" ]; then
  echo "App did not become ready in time."
  compose logs --tail 80 app || true
  exit 1
fi

echo "Postgres and app are running and managed env blocks were updated in:"
echo "  - $ROOT_ENV_LOCAL_FILE"
echo "  - $ROOT_ENV_FILE"
echo "App URL: http://localhost:$WEB_PORT"
echo "To follow app logs:"
echo "  docker compose --env-file $DOCKER_ENV_FILE -f $COMPOSE_FILE logs -f app"
