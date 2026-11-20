# Builds the web renderer and serves it with nginx. Build context is the repository root.
# The docs site is part of the landing page image (promo/Dockerfile).
FROM node:22-alpine AS build
WORKDIR /w/web
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY protocol /w/protocol
COPY web .
RUN npm run build

# Slim variant: no curl, libxslt or image libraries to keep patched. The upgrade takes Alpine fixes newer than the base.
FROM nginx:1.31-alpine-slim AS web
RUN apk upgrade --no-cache
COPY server/renderer/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /w/web/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD wget -qO- http://127.0.0.1/healthz || exit 1
