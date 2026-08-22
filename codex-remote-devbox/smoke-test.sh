#!/usr/bin/env bash
set -euo pipefail

image="${1:-ghcr.io/ytbits/codex-remote-devbox:codex-0.149.0-r1}"
expected_codex_version="${EXPECTED_CODEX_VERSION:-0.149.0}"
secret_marker="IMAGEYARD_SMOKE_SECRET_DO_NOT_BAKE_7e4fdd65"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-remote-devbox-smoke.XXXXXX")"
name_prefix="codex-remote-devbox-smoke-$$"
primary_container="${name_prefix}-primary"
restart_container="${name_prefix}-restart"
audit_container="${name_prefix}-audit"
missing_access_container="${name_prefix}-missing-access"
missing_host_container="${name_prefix}-missing-host"
empty_access_container="${name_prefix}-empty-access"
invalid_access_container="${name_prefix}-invalid-access"
mixed_invalid_access_container="${name_prefix}-mixed-invalid-access"
private_access_container="${name_prefix}-private-access"
invalid_host_container="${name_prefix}-invalid-host"
forward_pid=""

fail() {
  printf 'smoke-test: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local original_status=$?

  trap - EXIT INT TERM
  set +e

  if [ -n "$forward_pid" ]; then
    kill "$forward_pid" >/dev/null 2>&1 || true
    wait "$forward_pid" >/dev/null 2>&1 || true
  fi
  docker rm -f \
    "$primary_container" \
    "$restart_container" \
    "$audit_container" \
    "$missing_access_container" \
    "$missing_host_container" \
    "$empty_access_container" \
    "$invalid_access_container" \
    "$mixed_invalid_access_container" \
    "$private_access_container" \
    "$invalid_host_container" \
    >/dev/null 2>&1 || true

  # SSH sessions create UID 1000-owned state below the bind-mounted fixtures.
  # Remove it as container root before the unprivileged CI runner removes the
  # fixture root. The helper has no network, mounts only the exact directory
  # returned by mktemp, and cannot cross onto another filesystem.
  if [ -d "$fixture_dir" ] \
    && docker image inspect "$image" >/dev/null 2>&1; then
    docker run --rm \
      --network none \
      --user 0:0 \
      --entrypoint /bin/sh \
      --mount "type=bind,src=$fixture_dir,dst=/cleanup" \
      "$image" \
      -c 'find /cleanup -xdev -depth -mindepth 1 -delete' \
      >/dev/null 2>&1 || true
  fi
  rmdir -- "$fixture_dir" >/dev/null 2>&1 || true
  if [ -e "$fixture_dir" ]; then
    printf 'smoke-test: warning: could not remove fixture directory: %s\n' \
      "$fixture_dir" >&2
  fi

  exit "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for command_name in docker ssh ssh-keygen ssh-keyscan; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "required host command is unavailable: $command_name"
done

docker image inspect "$image" >/dev/null 2>&1 \
  || fail "image is not available locally: $image"

mkdir -p \
  "$fixture_dir/access" \
  "$fixture_dir/host" \
  "$fixture_dir/home" \
  "$fixture_dir/workspaces"
chmod 0777 "$fixture_dir/home" "$fixture_dir/workspaces"

ssh-keygen -q -t ed25519 -N '' -C "$secret_marker" -f "$fixture_dir/client_key"
ssh-keygen -q -t ed25519 -N '' -C unknown-smoke-client -f "$fixture_dir/unknown_key"
ssh-keygen -q -t ed25519 -N '' -C devbox-smoke-host -f "$fixture_dir/host/ssh_host_ed25519_key"
cp "$fixture_dir/client_key.pub" "$fixture_dir/access/authorized_keys"
chmod 0400 "$fixture_dir/client_key" "$fixture_dir/unknown_key" "$fixture_dir/host/ssh_host_ed25519_key"
chmod 0444 "$fixture_dir/access/authorized_keys"
: > "$fixture_dir/empty_authorized_keys"
printf '%s\n' 'not-an-authorized-key' > "$fixture_dir/invalid_authorized_keys"
cp "$fixture_dir/client_key.pub" "$fixture_dir/mixed_invalid_authorized_keys"
printf 'ssh-ed25519 AAAA %s\n' "$secret_marker" \
  >> "$fixture_dir/mixed_invalid_authorized_keys"
printf '%s\n' 'not-a-private-key' > "$fixture_dir/invalid_host_key"

start_container() {
  local container_name="$1"
  docker run --detach \
    --name "$container_name" \
    --publish 127.0.0.1::2222 \
    --mount "type=bind,src=$fixture_dir/access/authorized_keys,dst=/run/secrets/ssh-access/authorized_keys,readonly" \
    --mount "type=bind,src=$fixture_dir/host/ssh_host_ed25519_key,dst=/run/secrets/ssh-host/ssh_host_ed25519_key,readonly" \
    --mount "type=bind,src=$fixture_dir/home,dst=/home/codex" \
    --mount "type=bind,src=$fixture_dir/workspaces,dst=/workspaces" \
    "$image" >/dev/null
}

wait_for_ssh() {
  local container_name="$1"
  local known_hosts_file="$2"
  local port
  local attempt

  port="$(docker port "$container_name" 2222/tcp | awk -F: 'NR == 1 { print $NF }')"
  [ -n "$port" ] || fail "could not resolve the published SSH port for $container_name"

  for attempt in $(seq 1 60); do
    if [ "$(docker inspect --format '{{.State.Running}}' "$container_name")" != true ]; then
      docker logs "$container_name" >&2 || true
      fail "$container_name exited before SSH became ready"
    fi
    if ssh-keyscan -T 2 -p "$port" -t ed25519 127.0.0.1 > "$known_hosts_file" 2>/dev/null; then
      printf '%s\n' "$port"
      return 0
    fi
    sleep 0.5
  done

  docker logs "$container_name" >&2 || true
  fail "SSH did not become ready for $container_name"
}

ssh_command() {
  local known_hosts_file="$1"
  local port="$2"
  local identity_file="$3"
  local user="$4"
  shift 4

  ssh \
    -F /dev/null \
    -p "$port" \
    -i "$identity_file" \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o IdentitiesOnly=yes \
    -o LogLevel=ERROR \
    -o StrictHostKeyChecking=yes \
    -o "UserKnownHostsFile=$known_hosts_file" \
    "${user}@127.0.0.1" \
    "$@"
}

expect_start_failure() {
  local container_name="$1"
  local log_file="$2"
  local attempt
  local exit_code
  shift 2

  if ! docker run --detach --name "$container_name" "$@" "$image" \
    > /dev/null 2>"$log_file"; then
    fail "Docker could not create $container_name"
  fi

  for attempt in $(seq 1 20); do
    if [ "$(docker inspect --format '{{.State.Running}}' "$container_name")" != true ]; then
      exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$container_name")"
      docker logs "$container_name" >"$log_file" 2>&1 || true
      [ "$exit_code" -ne 0 ] || fail "$container_name exited successfully instead of failing closed"
      if grep -Fq "$secret_marker" "$log_file"; then
        fail "$container_name printed runtime key material"
      fi
      return 0
    fi
    sleep 0.25
  done

  docker logs "$container_name" >"$log_file" 2>&1 || true
  if grep -Fq "$secret_marker" "$log_file"; then
    fail "$container_name printed runtime key material"
  fi
  fail "$container_name remained running instead of failing closed"
}

if docker image inspect "$image" | grep -Fq "$secret_marker"; then
  fail "image metadata contains the smoke-test secret marker"
fi
if docker history --no-trunc "$image" | grep -Fq "$secret_marker"; then
  fail "image history contains the smoke-test secret marker"
fi

docker create --name "$audit_container" --entrypoint /bin/sh "$image" -c true >/dev/null
docker export "$audit_container" > "$fixture_dir/rootfs.tar"
tar -tf "$fixture_dir/rootfs.tar" > "$fixture_dir/rootfs.list"
if grep -E '(^|/)ssh_host_[^/]*_key$|(^|/)authorized_keys$' "$fixture_dir/rootfs.list" >/dev/null; then
  fail "image filesystem contains an SSH host or authorized key"
fi
if ! docker run --rm --entrypoint /bin/sh "$image" -c '
  set -eu
  test ! -e /home/codex/.codex/auth.json
  test ! -e /home/codex/.config/gh/hosts.yml
  if find /etc/ssh /home/codex /root -type f -exec grep -I -l -E "^-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----" {} + 2>/dev/null | grep -q .; then
    exit 1
  fi
  if grep -R -F -l "$1" /etc /home /root /usr/local 2>/dev/null | grep -q .; then
    exit 1
  fi
' sh "$secret_marker"; then
  fail "image filesystem contains credential material or the smoke-test marker"
fi

start_container "$primary_container"
primary_known_hosts="$fixture_dir/known_hosts.primary"
primary_port="$(wait_for_ssh "$primary_container" "$primary_known_hosts")"
primary_fingerprint="$(ssh-keygen -E sha256 -lf "$primary_known_hosts" | awk 'NR == 1 { print $2 }')"
[ -n "$primary_fingerprint" ] || fail "could not read the primary host fingerprint"

[ "$(docker inspect --format '{{.HostConfig.Privileged}}' "$primary_container")" = false ] \
  || fail "container unexpectedly requires privileged mode"
[ "$(docker image inspect --format '{{json .Config.ExposedPorts}}' "$image")" = '{"2222/tcp":{}}' ] \
  || fail "image exposes a port other than TCP 2222"

actual_mounts="$(docker inspect --format '{{range .Mounts}}{{println .Destination}}{{end}}' "$primary_container" | sed '/^$/d' | sort)"
expected_mounts="$(printf '%s\n' /home/codex /run/secrets/ssh-access/authorized_keys /run/secrets/ssh-host/ssh_host_ed25519_key /workspaces | sort)"
[ "$actual_mounts" = "$expected_mounts" ] \
  || fail "container uses unexpected mounts: $(printf '%s' "$actual_mounts" | paste -sd, -)"

docker exec "$primary_container" /bin/sh -c '
  set -eu
  test "$(ps -o comm= -p 1 | tr -d " ")" = tini
  sshd_pid="$(pgrep -o -x sshd)"
  test -n "$sshd_pid"
  test "$(ps -o user= -p "$sshd_pid" | tr -d " ")" = root
  test ! -S /var/run/docker.sock
'

clean_stdout="$(ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" codex \
  "printf '%s' codex-smoke-output" 2>"$fixture_dir/ssh.stderr")"
[ "$clean_stdout" = codex-smoke-output ] || fail "noninteractive SSH stdout contains a banner or MOTD"

[ "$(ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" codex 'id -u')" = 1000 ] \
  || fail "SSH session UID is not 1000"
[ "$(ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" codex 'id -g')" = 1000 ] \
  || fail "SSH session GID is not 1000"
[ "$(ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" codex \
  "getent passwd codex | cut -d: -f7")" = /bin/bash ] \
  || fail "codex login shell is not Bash"
[ "$(ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" codex 'sudo -n id -u')" = 0 ] \
  || fail "passwordless sudo is unavailable"

ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" codex \
  "set -eu; test -w /home/codex; test -w /workspaces; printf '%s' '$secret_marker' > /home/codex/.imageyard-smoke-state; printf '%s' '$secret_marker' > /workspaces/.imageyard-smoke-state"

[ "$(ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" codex 'codex --version')" = "codex-cli $expected_codex_version" ] \
  || fail "Codex version does not match $expected_codex_version"
ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" codex \
  'codex app-server --help >/dev/null'

ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" codex '
  set -eu
  for required_command in node npm python3 pip3 git git-lfs gh ssh gcc make curl jq rg fd bwrap ip ss ping lsof nc strace sudo tini; do
    command -v "$required_command" >/dev/null
  done
  python3 -m venv /tmp/imageyard-venv-smoke
  rm -rf /tmp/imageyard-venv-smoke
  for forbidden_command in docker dockerd podman nerdctl kubectl helm flux terraform tofu oras crane skopeo nvm pyenv; do
    if command -v "$forbidden_command" >/dev/null 2>&1; then
      exit 1
    fi
  done
'

ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" codex '
  set -eu
  listener_count="$(ss -H -lnt | wc -l)"
  ssh_listener_count="$(ss -H -lnt "sport = :2222" | wc -l)"
  test "$listener_count" -gt 0
  test "$listener_count" -eq "$ssh_listener_count"
' || fail "container listens on a port other than TCP 2222"
ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" codex \
  'if pgrep -x codex >/dev/null 2>&1; then exit 1; fi'

effective_sshd="$fixture_dir/sshd.effective"
docker exec "$primary_container" /usr/sbin/sshd -T -f /etc/ssh/sshd_config > "$effective_sshd"
for expected_setting in \
  'port 2222' \
  'permitrootlogin no' \
  'passwordauthentication no' \
  'kbdinteractiveauthentication no' \
  'allowagentforwarding no' \
  'allowtcpforwarding local' \
  'allowstreamlocalforwarding no' \
  'x11forwarding no' \
  'permituserenvironment no' \
  'printmotd no' \
  'banner none'; do
  grep -Fxq "$expected_setting" "$effective_sshd" \
    || fail "effective sshd configuration is missing: $expected_setting"
done
grep -Fq '127.0.0.1:*' "$effective_sshd" || fail "local forwarding is not restricted to loopback"
grep -Fq 'localhost:*' "$effective_sshd" || fail "localhost forwarding is not permitted"

if ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/unknown_key" codex true \
  >/dev/null 2>&1; then
  fail "an unknown SSH key authenticated successfully"
fi
if ssh_command "$primary_known_hosts" "$primary_port" "$fixture_dir/client_key" root true \
  >/dev/null 2>&1; then
  fail "root authenticated over SSH"
fi
password_probe_log="$fixture_dir/password-auth.log"
if ssh \
  -F /dev/null \
  -p "$primary_port" \
  -o ConnectTimeout=5 \
  -o NumberOfPasswordPrompts=0 \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o StrictHostKeyChecking=yes \
  -o "UserKnownHostsFile=$primary_known_hosts" \
  -vv \
  codex@127.0.0.1 true </dev/null >/dev/null 2>"$password_probe_log"; then
  fail "password authentication succeeded"
fi
grep -E 'Authentications that can continue: publickey[[:space:]]*$' "$password_probe_log" >/dev/null \
  || fail "server did not advertise public-key-only authentication"
if grep -E 'Authentications that can continue:.*(password|keyboard-interactive)' "$password_probe_log" >/dev/null; then
  fail "server advertised password or keyboard-interactive authentication"
fi

ssh \
  -F /dev/null \
  -p "$primary_port" \
  -i "$fixture_dir/client_key" \
  -N \
  -R 0:127.0.0.1:22 \
  -o BatchMode=yes \
  -o ConnectTimeout=5 \
  -o ExitOnForwardFailure=yes \
  -o IdentitiesOnly=yes \
  -o LogLevel=ERROR \
  -o StrictHostKeyChecking=yes \
  -o "UserKnownHostsFile=$primary_known_hosts" \
  codex@127.0.0.1 >/dev/null 2>&1 &
forward_pid=$!
forward_exited=false
for attempt in $(seq 1 20); do
  if ! kill -0 "$forward_pid" >/dev/null 2>&1; then
    forward_exited=true
    break
  fi
  sleep 0.25
done
if [ "$forward_exited" != true ]; then
  kill "$forward_pid" >/dev/null 2>&1 || true
  wait "$forward_pid" >/dev/null 2>&1 || true
  forward_pid=""
  fail "remote port forwarding remained active"
fi
if wait "$forward_pid"; then
  forward_pid=""
  fail "remote port forwarding succeeded"
fi
forward_pid=""

docker rm -f "$primary_container" >/dev/null
start_container "$restart_container"
restart_known_hosts="$fixture_dir/known_hosts.restart"
restart_port="$(wait_for_ssh "$restart_container" "$restart_known_hosts")"
restart_fingerprint="$(ssh-keygen -E sha256 -lf "$restart_known_hosts" | awk 'NR == 1 { print $2 }')"
[ "$restart_fingerprint" = "$primary_fingerprint" ] || fail "host fingerprint changed after restart"

[ "$(ssh_command "$restart_known_hosts" "$restart_port" "$fixture_dir/client_key" codex \
  'cat /home/codex/.imageyard-smoke-state')" = "$secret_marker" ] \
  || fail "home state did not persist across replacement"
[ "$(ssh_command "$restart_known_hosts" "$restart_port" "$fixture_dir/client_key" codex \
  'cat /workspaces/.imageyard-smoke-state')" = "$secret_marker" ] \
  || fail "workspace state did not persist across replacement"

expect_start_failure "$missing_access_container" "$fixture_dir/missing-access.log" \
  --mount "type=bind,src=$fixture_dir/host/ssh_host_ed25519_key,dst=/run/secrets/ssh-host/ssh_host_ed25519_key,readonly"
expect_start_failure "$missing_host_container" "$fixture_dir/missing-host.log" \
  --mount "type=bind,src=$fixture_dir/access/authorized_keys,dst=/run/secrets/ssh-access/authorized_keys,readonly"
expect_start_failure "$empty_access_container" "$fixture_dir/empty-access.log" \
  --mount "type=bind,src=$fixture_dir/empty_authorized_keys,dst=/run/secrets/ssh-access/authorized_keys,readonly" \
  --mount "type=bind,src=$fixture_dir/host/ssh_host_ed25519_key,dst=/run/secrets/ssh-host/ssh_host_ed25519_key,readonly"
expect_start_failure "$invalid_access_container" "$fixture_dir/invalid-access.log" \
  --mount "type=bind,src=$fixture_dir/invalid_authorized_keys,dst=/run/secrets/ssh-access/authorized_keys,readonly" \
  --mount "type=bind,src=$fixture_dir/host/ssh_host_ed25519_key,dst=/run/secrets/ssh-host/ssh_host_ed25519_key,readonly"
expect_start_failure "$mixed_invalid_access_container" "$fixture_dir/mixed-invalid-access.log" \
  --mount "type=bind,src=$fixture_dir/mixed_invalid_authorized_keys,dst=/run/secrets/ssh-access/authorized_keys,readonly" \
  --mount "type=bind,src=$fixture_dir/host/ssh_host_ed25519_key,dst=/run/secrets/ssh-host/ssh_host_ed25519_key,readonly"
expect_start_failure "$private_access_container" "$fixture_dir/private-access.log" \
  --mount "type=bind,src=$fixture_dir/client_key,dst=/run/secrets/ssh-access/authorized_keys,readonly" \
  --mount "type=bind,src=$fixture_dir/host/ssh_host_ed25519_key,dst=/run/secrets/ssh-host/ssh_host_ed25519_key,readonly"
expect_start_failure "$invalid_host_container" "$fixture_dir/invalid-host.log" \
  --mount "type=bind,src=$fixture_dir/access/authorized_keys,dst=/run/secrets/ssh-access/authorized_keys,readonly" \
  --mount "type=bind,src=$fixture_dir/invalid_host_key,dst=/run/secrets/ssh-host/ssh_host_ed25519_key,readonly"

printf 'Codex remote devbox smoke tests passed for %s\n' "$image"
