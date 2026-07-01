#!/bin/sh
set -eu

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "codex-entrypoint: required environment variable $name is not set" >&2
    exit 1
  fi
}

require_env MULTICA_SERVER_URL
require_env MULTICA_TOKEN
require_env OPENAI_API_KEY

: "${HOSTNAME:=multica-runtime}"
: "${MULTICA_APP_URL:=$MULTICA_SERVER_URL}"
: "${MULTICA_DAEMON_ID:=$HOSTNAME}"
: "${MULTICA_DAEMON_DEVICE_NAME:=$HOSTNAME}"
: "${MULTICA_AGENT_RUNTIME_NAME:=K3s Codex Runtime}"
: "${MULTICA_DAEMON_MAX_CONCURRENT_TASKS:=1}"

export MULTICA_APP_URL
export MULTICA_DAEMON_ID
export MULTICA_DAEMON_DEVICE_NAME
export MULTICA_AGENT_RUNTIME_NAME
export MULTICA_DAEMON_MAX_CONCURRENT_TASKS

mkdir -p "$HOME/.multica" "$HOME/multica_workspaces"

node <<'EOF'
const fs = require("fs");
const path = require("path");

const configPath = path.join(process.env.HOME, ".multica", "config.json");
const config = {
  server_url: process.env.MULTICA_SERVER_URL,
  app_url: process.env.MULTICA_APP_URL,
  token: process.env.MULTICA_TOKEN,
};

fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
fs.chmodSync(configPath, 0o600);
EOF

exec multica daemon start \
  --foreground \
  --server-url "$MULTICA_SERVER_URL" \
  --daemon-id "$MULTICA_DAEMON_ID" \
  --device-name "$MULTICA_DAEMON_DEVICE_NAME" \
  --runtime-name "$MULTICA_AGENT_RUNTIME_NAME" \
  --max-concurrent-tasks "$MULTICA_DAEMON_MAX_CONCURRENT_TASKS" \
  --no-auto-update
