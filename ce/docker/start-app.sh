#!/usr/bin/env sh
set -eu

lock_hash="$(sha256sum package-lock.json | awk '{print $1}')"
runtime_signature="$(node -p '`${process.version}|${process.versions.modules}|${process.platform}|${process.arch}`')"
install_signature="${lock_hash}|${runtime_signature}"
current_signature="$(cat node_modules/.install.signature 2>/dev/null || true)"

if [ "$current_signature" != "$install_signature" ]; then
  if ! npm ci --no-audit --no-fund; then
    echo "npm ci failed (lockfile mismatch). Falling back to npm install to recover; package-lock.json may be updated." >&2
    npm install --no-audit --no-fund
  fi
  lock_hash="$(sha256sum package-lock.json | awk '{print $1}')"
  install_signature="${lock_hash}|${runtime_signature}"
  printf '%s\n' "$install_signature" > node_modules/.install.signature
fi

npm run dev:prisma
npm run dev -- --hostname 0.0.0.0 --port "${WEB_PORT:-3003}"
