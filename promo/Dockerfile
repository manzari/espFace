# syntax=docker/dockerfile:1
# Landing page plus the docs site. Build context is the repository root:
# promo/ is the content, promo/engine/ renders it, docs/site/ becomes /docs/.
# engine/ is a copy of the apppage engine at commit 81fb0e3 (its bin, config,
# src and build files), with the Impressum citing the DDG.

# Docs: the API reference is generated from the firmware headers on every build.
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

FROM ruby:3.2-alpine AS builder

RUN apk add --no-cache build-base ca-certificates curl git jq nodejs npm

WORKDIR /site

COPY promo/engine/Gemfile promo/engine/Gemfile.lock ./
RUN bundle install

COPY promo/engine/package.json promo/engine/package-lock.json ./
RUN npm ci --ignore-scripts

COPY promo/engine/ .

# Legal pages come from the engrossify API. This layer depends only on the
# engine and the two files below, so edits to texts and images do not render
# them again.
COPY promo/_config.yml promo/engrossify.yaml /project/
ARG ENGROSSIFY_URL=https://legal.guestlist.ink
ARG LEGAL_RENDER_VERSION=1
# Local builds only: placeholder legal pages instead of failing without the key.
ARG ALLOW_PLACEHOLDER_LEGAL=0
RUN --mount=type=secret,id=engrossify_api_key \
    echo "legal render v${LEGAL_RENDER_VERSION}" && \
    if [ "$ALLOW_PLACEHOLDER_LEGAL" = "1" ]; then \
        echo "WARNING: ALLOW_PLACEHOLDER_LEGAL=1, shipping placeholder legal pages" >&2; \
        sh bin/render-legal.sh /project; \
    elif [ ! -s /run/secrets/engrossify_api_key ]; then \
        echo "ERROR: build secret 'engrossify_api_key' is missing or empty (set ENGROSSIFY_API_KEY)." >&2; \
        exit 1; \
    else \
        ENGROSSIFY_API_KEY="$(cat /run/secrets/engrossify_api_key)" \
        ENGROSSIFY_URL="$ENGROSSIFY_URL" \
        sh bin/render-legal.sh /project; \
    fi

COPY promo/brand.css /project/
COPY promo/i18n /project/i18n
COPY promo/images /project/images
# Optional webfonts for brand.css: the pattern matches nothing until promo/fonts exists.
COPY promo/font[s] /project/fonts
RUN sh bin/apply-content.sh /project

RUN mkdir -p src/assets/css/vendor/fontawesome src/assets/fonts/fontawesome src/assets/fonts/inter && \
    npm run copy-assets && \
    sed -i 's|../webfonts/|/assets/fonts/fontawesome/|g' src/assets/css/vendor/fontawesome/all.min.css

RUN bundle exec jekyll build --source src && \
    find _site -type d -exec chmod 755 {} + && \
    find _site -type f -exec chmod 644 {} +

FROM nginx:alpine

COPY --from=builder /site/_site /usr/share/nginx/html
COPY --from=docs /w/docs/site/.vitepress/dist /usr/share/nginx/html/docs
COPY --from=builder /site/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /site/nginx-security-headers.conf /etc/nginx/snippets/security-headers.conf

# docs.conf serves /docs/; renderer-host.conf keeps the paths of the old renderer
# host answering. Both go into the engine's server block, whose last line closes it.
# VitePress pages need inline scripts and styles, so they get the engine's headers
# with a wider CSP.
COPY promo/docs.conf promo/renderer-host.conf /etc/nginx/snippets/
RUN sed -e "s/style-src 'self'/style-src 'self' 'unsafe-inline'/" \
        -e "s/script-src 'self'/script-src 'self' 'unsafe-inline'/" \
        /etc/nginx/snippets/security-headers.conf > /etc/nginx/snippets/docs-security-headers.conf && \
    [ "$(grep -o "'unsafe-inline'" /etc/nginx/snippets/docs-security-headers.conf | wc -l)" = 2 ] && \
    sed -i '$ s|^}$|    include /etc/nginx/snippets/docs.conf;\n    include /etc/nginx/snippets/renderer-host.conf;\n}|' /etc/nginx/conf.d/default.conf && \
    grep -q docs.conf /etc/nginx/conf.d/default.conf && \
    grep -q renderer-host.conf /etc/nginx/conf.d/default.conf && \
    nginx -t

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
