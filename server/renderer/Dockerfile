# Builds the web renderer and the docs site and serves both with nginx. Build context is the repository root.
FROM node:22-alpine AS build
WORKDIR /w/web
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY protocol /w/protocol
COPY web .
RUN npm run build

FROM node:22-alpine AS docs
WORKDIR /w/docs/site
COPY docs/site/package.json docs/site/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY protocol/PROTOCOL.md /w/protocol/PROTOCOL.md
COPY firmware/src/Face.h /w/firmware/src/Face.h
COPY firmware/src/ui/Ui.h /w/firmware/src/ui/Ui.h
COPY firmware/README.md /w/firmware/README.md
COPY web/src/icons.json /w/web/src/icons.json
COPY docs/site .
RUN npm run build

FROM nginx:1.27-alpine
COPY server/renderer/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /w/web/dist /usr/share/nginx/html
COPY --from=docs /w/docs/site/.vitepress/dist /usr/share/nginx/html/docs
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD wget -qO- http://127.0.0.1/healthz || exit 1
