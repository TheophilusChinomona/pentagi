# ============================================================================
# Athena Hermes Super-Agent gateway image
# - Base: upstream Hermes/Athena runtime image
# - Adds: docker CLI, Athena engagement scripts, Athena skills, super-agent
#   command wrappers, and a bootstrap entrypoint that prepares runtime paths.
# ============================================================================

ARG BASE_IMAGE=registry.gitlab.com/chinomonatinotenda19/athena:stable
FROM ${BASE_IMAGE}

USER root

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

# Bundle Athena scripts and skills into the gateway image.
COPY --chown=hermes:hermes ../scripts /opt/athena/scripts
COPY --chown=hermes:hermes ../skills /opt/athena/skills
COPY --chown=hermes:hermes ../docker/entrypoint-super-agent.sh /opt/athena/entrypoint-super-agent.sh

# Hermes can call these wrappers via terminal commands:
# - athena-engage <target> [engagement-id]
# - athena-teardown <engagement-id>
# - athena-code-audit <repo-path-or-url> [output-dir]
RUN chmod +x /opt/athena/scripts/*.sh /opt/athena/entrypoint-super-agent.sh && \
    ln -sf /opt/athena/scripts/run-engagement.sh /usr/local/bin/athena-engage && \
    ln -sf /opt/athena/scripts/teardown-engagement.sh /usr/local/bin/athena-teardown && \
    ln -sf /opt/athena/scripts/run-code-audit.sh /usr/local/bin/athena-code-audit

USER hermes
ENTRYPOINT ["/opt/athena/entrypoint-super-agent.sh"]
