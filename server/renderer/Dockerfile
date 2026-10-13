# Builds the web renderer and serves dist/ with nginx. Build context is the repository root.
FROM node:22-alpine AS build
WORKDIR /w/web
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY protocol /w/protocol
COPY web .
RUN npm run build

FROM nginx:1.27-alpine
COPY server/renderer/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /w/web/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD wget -qO- http://127.0.0.1/healthz || exit 1
