# syntax=docker/dockerfile:1

# Debian 12.15 (2026-08-03), multi-platform index digest.
ARG FLUTTER_BUILDER_IMAGE=debian:bookworm-20260803-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241
# NGINX unprivileged 1.31.3 on Alpine 3.24, multi-platform index digest.
ARG NGINX_RUNTIME_IMAGE=ghcr.io/nginx/nginx-unprivileged:1.31.3-alpine3.24@sha256:59a7114c40708c891cc71f0338d116d9410d7c2a72d8d2e61ce4148219a20b10

FROM ${FLUTTER_BUILDER_IMAGE} AS builder

ARG FLUTTER_VERSION=3.44.7
ARG FLUTTER_ARCHIVE_SHA256=a0edd646c159c0e816788c0e46a4f071199c1320495898f5a679599b583a05a4

ENV CI=true \
    DART_TOOL_DISABLE_ANALYTICS=true \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    PUB_CACHE=/tmp/pub-cache \
    PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl git xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,id=arion-flutter-sdk-download,target=/var/cache/flutter,sharing=locked \
    curl --fail --location --retry 3 --retry-all-errors --retry-delay 2 --continue-at - \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        --output "/var/cache/flutter/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && echo "${FLUTTER_ARCHIVE_SHA256}  /var/cache/flutter/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        | sha256sum --check --strict \
    && tar --extract --xz \
        --file "/var/cache/flutter/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        --directory /opt \
    && git config --global --add safe.directory /opt/flutter \
    && flutter --version \
    && flutter precache --web

WORKDIR /src/client

COPY .flutter-version /tmp/arion-flutter-version
COPY client/pubspec.yaml client/pubspec.lock ./

RUN test "$(tr -d '\r\n' < /tmp/arion-flutter-version)" = "${FLUTTER_VERSION}" \
    && flutter pub get --enforce-lockfile

COPY client/.metadata ./
COPY client/analysis_options.yaml ./
COPY client/lib ./lib
COPY client/web ./web

RUN flutter build web --release --no-web-resources-cdn \
    && test -s build/web/index.html \
    && test -s build/web/flutter_bootstrap.js \
    && test -s build/web/main.dart.js

FROM ${NGINX_RUNTIME_IMAGE} AS runtime

COPY --chown=101:101 client/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /src/client/build/web /usr/share/nginx/html

USER 101:101

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["wget", "-q", "-T", "2", "-O", "/dev/null", "http://127.0.0.1:8080/index.html"]

FROM runtime AS production
