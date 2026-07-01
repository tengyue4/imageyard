ARG MULTICA_VERSION=v0.3.29
FROM ghcr.io/multica-ai/multica-backend:${MULTICA_VERSION}

ARG CODEX_VERSION=0.142.4

LABEL org.opencontainers.image.title="Multica Codex Runtime"
LABEL org.opencontainers.image.description="Codex-first Multica daemon runtime image for Kubernetes-hosted agents"
LABEL org.opencontainers.image.source="https://github.com/tengyue4/imageyard"

RUN apk add --no-cache \
    bash \
    bubblewrap \
    ca-certificates \
    git \
    github-cli \
    nodejs \
    npm \
    openssh-client \
  && ln -sf /app/multica /usr/local/bin/multica \
  && npm install -g "@openai/codex@${CODEX_VERSION}" \
  && npm cache clean --force \
  && addgroup -S multica \
  && adduser -S -D -h /home/multica -s /bin/sh -G multica multica \
  && mkdir -p /home/multica/.multica /home/multica/multica_workspaces \
  && chown -R multica:multica /home/multica

COPY --chmod=0755 codex-entrypoint.sh /usr/local/bin/codex-entrypoint.sh

ENV HOME=/home/multica
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV MULTICA_CODEX_PATH=codex

USER multica
WORKDIR /home/multica/multica_workspaces

ENTRYPOINT ["codex-entrypoint.sh"]
