ARG MULTICA_VERSION=v0.3.29
FROM ghcr.io/multica-ai/multica-backend:${MULTICA_VERSION}

ARG CLAUDE_CODE_VERSION=2.1.197

LABEL org.opencontainers.image.title="Multica Claude Runtime"
LABEL org.opencontainers.image.description="Claude Code-first Multica daemon runtime image for Kubernetes-hosted agents"
LABEL org.opencontainers.image.source="https://github.com/tengyue4/imageyard"

RUN apk add --no-cache \
    bash \
    ca-certificates \
    git \
    github-cli \
    nodejs \
    npm \
    openssh-client \
  && ln -sf /app/multica /usr/local/bin/multica \
  && npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  && npm cache clean --force \
  && addgroup -S multica \
  && adduser -S -D -h /home/multica -s /bin/sh -G multica multica \
  && mkdir -p /home/multica/.multica /home/multica/multica_workspaces \
  && chown -R multica:multica /home/multica

COPY --chmod=0755 claude-entrypoint.sh /usr/local/bin/claude-entrypoint.sh

ENV HOME=/home/multica
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV MULTICA_CLAUDE_PATH=claude

USER multica
WORKDIR /home/multica/multica_workspaces

ENTRYPOINT ["claude-entrypoint.sh"]
