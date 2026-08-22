#!/bin/sh
set -eu

authorized_keys_source=/run/secrets/ssh-access/authorized_keys
host_key_source=/run/secrets/ssh-host/ssh_host_ed25519_key
runtime_dir=/run/codex-remote-devbox
authorized_keys_runtime="$runtime_dir/authorized_keys"
host_key_runtime="$runtime_dir/ssh_host_ed25519_key"

fail() {
  printf '%s\n' "codex-remote-devbox: $*" >&2
  exit 1
}

[ "$(id -u)" = 0 ] || fail "entrypoint must run as root"

for required_file in "$authorized_keys_source" "$host_key_source"; do
  [ -f "$required_file" ] || fail "required runtime key file is missing: $required_file"
  [ -r "$required_file" ] || fail "required runtime key file is unreadable: $required_file"
  [ -s "$required_file" ] || fail "required runtime key file is empty: $required_file"
done

install -d -o root -g root -m 0755 /run/sshd
install -d -o root -g root -m 0755 "$runtime_dir"
install -o root -g root -m 0644 "$authorized_keys_source" "$authorized_keys_runtime"
install -o root -g root -m 0600 "$host_key_source" "$host_key_runtime"

awk '
  /^[[:space:]]*($|#)/ { next }
  $1 ~ /^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)$/ &&
    $2 ~ /^[A-Za-z0-9+\/=]+$/ { valid_keys++; next }
  { exit 1 }
  END { if (valid_keys == 0) exit 1 }
' "$authorized_keys_runtime" \
  || fail "authorized_keys must contain only bare OpenSSH public keys"
ssh-keygen -l -f "$authorized_keys_runtime" >/dev/null 2>&1 \
  || fail "authorized_keys contains invalid public key data"

host_key_type="$(ssh-keygen -y -f "$host_key_runtime" 2>/dev/null | awk 'NR == 1 { print $1 }')"
[ "$host_key_type" = ssh-ed25519 ] \
  || fail "host key is not a valid Ed25519 private key"

for writable_path in /home/codex /workspaces; do
  [ -d "$writable_path" ] || fail "required path is missing: $writable_path"
  sudo -n -u codex -- test -w "$writable_path" \
    || fail "required path is not writable by codex: $writable_path"
done

[ "$(id -u codex)" = 1000 ] || fail "codex UID is not 1000"
[ "$(id -g codex)" = 1000 ] || fail "codex GID is not 1000"
[ "$(getent passwd codex | cut -d: -f7)" = /bin/bash ] \
  || fail "codex login shell is not /bin/bash"

/usr/sbin/sshd -t -f /etc/ssh/sshd_config \
  || fail "OpenSSH configuration validation failed"

exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
