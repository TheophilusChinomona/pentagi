# ============================================================================
# Gateway extension — adds docker-ce-cli to the upstream athena image so the
# agent's terminal_tool can shell out to `docker` against the sibling DinD
# daemon defined in docker-compose.yml.
#
# This is the "bootstrap" gateway. Long-term plan: have Athena self-strip
# the upstream image (drop messaging/voice/web/playwright bloat) and replace
# this with a fully custom pentest gateway. Until then, this thin layer
# unblocks docker-in-docker without modifying the upstream athena repo.
#
# Build (locally, from athena-pentest repo root):
#   docker build \
#     --build-arg IMAGE_TAG=stable \
#     -t registry.gitlab.com/chinomonatinotenda19/athena-pentest/gateway:stable \
#     -f docker/gateway.Dockerfile docker/
#
# Push (requires `docker login registry.gitlab.com` with a deploy or PAT
#       scoped to write_registry on athena-pentest):
#   docker push registry.gitlab.com/chinomonatinotenda19/athena-pentest/gateway:stable
# ============================================================================

ARG IMAGE_TAG=stable
FROM registry.gitlab.com/chinomonatinotenda19/athena:${IMAGE_TAG}

USER root

# Install docker-ce-cli (client only, ~30MB) from Docker's official apt repo.
# Not docker.io — that pulls the full daemon stub (~80MB) we never start, since
# the daemon is the sibling `dind` service the gateway talks to over TCP+TLS.
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    . /etc/os-release && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Hand control back to the upstream image's runtime user. The athena entrypoint
# (/opt/hermes/docker/entrypoint.sh) is unchanged and inherited from the base.
USER hermes
