FROM node:22-alpine
WORKDIR /app
COPY tools/fake-device/package.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY tools/fake-device/src ./src
EXPOSE 8080
ENTRYPOINT ["node", "src/index.mjs"]
