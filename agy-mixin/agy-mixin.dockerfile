# syntax=docker/dockerfile:1
# hadolint global ignore=DL3002
# The installer targets the agent's home and has no relocatable prefix. Run it
# unchanged on the workload base, then copy the complete ~/.local tree into a
# scratch overlay. Keep this recipe in sync with ../agy.dockerfile.
FROM docker/sandbox-templates:shell-docker@sha256:1560168ac5fb9ce23d413c878349334c5845c07e264cd675d7867f0c78ad1761 AS build
USER agent
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=secret,id=proxy_ca,required=false,uid=1000,gid=1000,mode=0444 \
    set -eu; \
    if [ -s /run/secrets/proxy_ca ]; then \
      cat /etc/ssl/certs/ca-certificates.crt /run/secrets/proxy_ca > /tmp/build-ca.crt; \
      export SSL_CERT_FILE=/tmp/build-ca.crt; \
    fi; \
    curl -fsSL --compressed https://antigravity.google/cli/install.sh | bash; \
    test -x /home/agent/.local/bin/agy; \
    rm -f /tmp/build-ca.crt

USER root
RUN mkdir -p /out/home/agent /out/usr/local/bin \
 && cp -a /home/agent/.local /out/home/agent/.local \
 && chown -R 1000:1000 /out/home/agent \
 && ln -s /home/agent/.local/bin/agy /out/usr/local/bin/agy

# A mixin overlay must not set USER; the composed workload owns runtime identity.
FROM scratch
COPY --from=build /out /
ENV SSH_CONNECTION="sandbox 0 sandbox 0"
