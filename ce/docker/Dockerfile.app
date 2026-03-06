ARG NODE_IMAGE=node:24-alpine
FROM ${NODE_IMAGE}

# Prisma needs OpenSSL at runtime; libc6-compat helps native deps on musl.
RUN apk add --no-cache openssl libc6-compat

WORKDIR /app
