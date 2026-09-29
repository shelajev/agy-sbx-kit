# syntax=docker/dockerfile:1
# v2's sandbox.image, now the workload content.
FROM docker/sandbox-templates:shell-docker@sha256:1560168ac5fb9ce23d413c878349334c5845c07e264cd675d7867f0c78ad1761

# The vendor installer has no stable version pin and agy self-updates. Install
# the same floating channel the v2 create-time hook used, but bake it into the
# artifact so sandbox creation does not download executable content.
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

# agy detects remote environments and switches to copy/paste OAuth instead of
# trying to launch a browser and callback listener inside the sandbox.
ENV SSH_CONNECTION="sandbox 0 sandbox 0"
WORKDIR /home/agent/workspace
ENTRYPOINT ["agy"]
CMD ["--dangerously-skip-permissions", "--mode=accept-edits"]
