# Pinned arduino-lint for Library Manager compliance checks. Usage: tools/release/lint-library.sh
FROM alpine:3.20
ARG LINT_VERSION=1.3.0
RUN wget -qO- "https://github.com/arduino/arduino-lint/releases/download/${LINT_VERSION}/arduino-lint_${LINT_VERSION}_Linux_64bit.tar.gz" \
  | tar xz -C /usr/local/bin arduino-lint
ENTRYPOINT ["arduino-lint"]
