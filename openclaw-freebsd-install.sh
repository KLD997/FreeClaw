#!/bin/sh
# openclaw-freebsd-install.sh
#
# Install/repair OpenClaw inside a FreeBSD jail using the known-good service layout:
# - Jail service: openclaw_gateway (wrapper-managed PID + PATH/HOME)
# - Clipboard FreeBSD module stub (prevents startup crash on some versions)
#
# Run this on the HOST; it jexec's into the jail.
#
# Env overrides:
#   JAIL_NAME=openclaw
#   OC_USER=kld
#   JAIL_IP=10.30.0.10
#   OC_PORT=18789
#   GATEWAY_SERVICE=openclaw_gateway
#
set -eu

JAIL_NAME="${JAIL_NAME:-openclaw}"
OC_USER="${OC_USER:-kld}"
JAIL_IP="${JAIL_IP:-10.30.0.10}"
OC_PORT="${OC_PORT:-18789}"
GATEWAY_SERVICE="${GATEWAY_SERVICE:-openclaw_gateway}"

# ---------- helpers ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
msg()  { printf "${GREEN}==>${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}WARN:${NC} %s\n" "$*"; }
err()  { printf "${RED}ERROR:${NC} %s\n" "$*" >&2; exit 1; }

SUDO=""
if command -v doas >/dev/null 2>&1; then
  SUDO=doas
elif command -v sudo >/dev/null 2>&1; then
  SUDO=sudo
fi

need_rootish() {
  if [ "$(id -u)" -eq 0 ]; then return 0; fi
  [ -n "$SUDO" ] || err "Need root privileges (install doas/sudo or run as root)."
}

run_host() {
  if [ "$(id -u)" -eq 0 ]; then
    command "$@"
  else
    "$SUDO" "$@"
  fi
}

jexec() { need_rootish; run_host jexec "$JAIL_NAME" "$@"; }
jexec_sh() { need_rootish; run_host jexec "$JAIL_NAME" sh -lc "$*"; }

ensure_jail_running() {
  need_rootish
  if run_host jls -j "$JAIL_NAME" >/dev/null 2>&1; then return 0; fi
  warn "Jail '$JAIL_NAME' not running; starting it…"
  run_host service jail onestart "$JAIL_NAME" >/dev/null 2>&1 || run_host service jail start "$JAIL_NAME" >/dev/null 2>&1 || \
    err "Could not start jail '$JAIL_NAME'. Fix /etc/jail.conf networking first."
  msg "Jail started."
}

host_uid_gid() {
  # Prefer matching the host user's UID/GID if it exists.
  if id "$OC_USER" >/dev/null 2>&1; then
    UID="$(id -u "$OC_USER")"
    GID="$(id -g "$OC_USER")"
  else
    # fallback; you can adjust if you want
    UID="1001"
    GID="1001"
  fi
  echo "$UID:$GID"
}

ensure_pkg_bootstrap() {
  jexec_sh "env ASSUME_ALWAYS_YES=YES pkg bootstrap -f >/dev/null 2>&1 || true"
}

ensure_user() {
  ids="$(host_uid_gid)"
  UID="${ids%:*}"
  GID="${ids#*:}"

  if jexec pw usershow "$OC_USER" >/dev/null 2>&1; then
    msg "User '$OC_USER' exists in jail."
    return 0
  fi

  msg "Creating jail user '$OC_USER' (uid=$UID gid=$GID)…"
  jexec_sh "pw groupadd -n '$OC_USER' -g '$GID' 2>/dev/null || true"
  jexec_sh "pw useradd -n '$OC_USER' -u '$UID' -g '$GID' -m -d /home/'$OC_USER' -s /bin/sh"
}

ensure_deps() {
  msg "Installing jail packages (node + npm + tools)…"
  jexec_sh "pkg update -f >/dev/null"
  # Prefer node22; fallback to node20 if needed.
  jexec_sh "pkg install -y ca_root_nss curl git jq tmux >/dev/null"
  if ! jexec_sh "pkg install -y node22 npm-node22 >/dev/null"; then
    jexec_sh "pkg install -y node20 npm-node20 >/dev/null"
  fi
}

install_openclaw() {
  msg "Installing/upgrading OpenClaw (npm -g)…"
  jexec_sh "npm install -g openclaw@latest >/dev/null"
  jexec command -v openclaw >/dev/null 2>&1 || err "OpenClaw not found in PATH inside jail after install."
}

install_clipboard_stub() {
  msg "Ensuring FreeBSD clipboard module stub exists (prevents startup crash)…"
  jexec_sh '
set -eu
BASE="/usr/local/lib/node_modules/openclaw/node_modules/@mariozechner"
MOD="$BASE/clipboard-freebsd-x64"
[ -d "$BASE" ] || exit 0

if [ -f "$MOD/index.js" ]; then
  exit 0
fi

mkdir -p "$MOD"
cat > "$MOD/package.json" <<EOF
{
  "name": "@mariozechner/clipboard-freebsd-x64",
  "version": "0.0.0-localstub",
  "main": "index.js",
  "private": true
}
EOF

cat > "$MOD/index.js" <<'"'"'EOF'"'"'
"use strict";
module.exports = new Proxy({}, {
  get(_t, prop) {
    if (prop === "__esModule") return false;
    return function () {
      throw new Error("[openclaw] Clipboard native bindings unavailable on FreeBSD (stub).");
    };
  }
});
EOF
chown -R root:wheel "$MOD"
chmod -R 0555 "$MOD"
'
}

write_token_and_config() {
  msg "Ensuring token + config exist for '$OC_USER'…"

  # Token
  if ! jexec_sh "su - '$OC_USER' -c 'test -f ~/.openclaw/gateway.token'"; then
    jexec_sh "su - '$OC_USER' -c 'umask 077; mkdir -p ~/.openclaw; openssl rand -hex 32 > ~/.openclaw/gateway.token'"
  fi

  TOKEN="$(jexec_sh "su - '$OC_USER' -c 'cat ~/.openclaw/gateway.token'" | tr -d '\r' | tail -n1)"

  # Config (only create if missing; do not overwrite)
  if jexec_sh "su - '$OC_USER' -c 'test -f ~/.openclaw/openclaw.json'"; then
    warn "Config exists: /home/$OC_USER/.openclaw/openclaw.json (leaving as-is)"
  else
    jexec_sh "su - '$OC_USER' -c 'cat > ~/.openclaw/openclaw.json <<JSON
{
  \"gateway\": {
    \"mode\": \"local\",
    \"port\": $OC_PORT,
    \"auth\": { \"mode\": \"token\", \"token\": \"${TOKEN}\" },
    \"controlUi\": { \"enabled\": true, \"basePath\": \"/\", \"allowInsecureAuth\": true }
  },
  \"agents\": { \"defaults\": { \"workspace\": \"/home/$OC_USER/ocDownloads\" } }
}
JSON
chmod 600 ~/.openclaw/openclaw.json'"
  fi

  # Ensure env file exists (keys)
  jexec_sh "su - '$OC_USER' -c 'touch ~/.openclaw/.env && chmod 600 ~/.openclaw/.env'"
}

install_gateway_wrapper_and_service() {
  msg "Installing jail wrapper + rc.d service ($GATEWAY_SERVICE)…"

  # Wrapper
  jexec_sh "install -d -m 0755 /usr/local/libexec"
  jexec_sh "cat > /usr/local/libexec/openclaw-gateway-run <<'SH'
#!/bin/sh
set -eu

USER=\"${OC_USER}\"
PIDFILE=\"/var/run/openclaw/openclaw_gateway.pid\"
LOG=\"/var/log/openclaw_gateway.log\"

export PATH=\"/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin\"
export HOME=\"/home/\${USER}\"

mkdir -p /var/run/openclaw /var/log
chown -R \"\${USER}:\${USER}\" /var/run/openclaw /var/log 2>/dev/null || true
touch \"\$LOG\"
chown \"\${USER}:\${USER}\" \"\$LOG\" 2>/dev/null || true

command -v node >/dev/null 2>&1 || { echo \"node not found in PATH=\$PATH\" >> \"\$LOG\"; exit 1; }

if [ -f \"\$PIDFILE\" ] && kill -0 \"\$(cat \"\$PIDFILE\")\" 2>/dev/null; then
  exit 0
fi

/usr/local/bin/openclaw gateway >> \"\$LOG\" 2>&1 &
echo \$! > \"\$PIDFILE\"

sleep 0.2
kill -0 \"\$(cat \"\$PIDFILE\")\" 2>/dev/null
SH
chmod 0555 /usr/local/libexec/openclaw-gateway-run"

  # rc.d
  jexec_sh "cat > /usr/local/etc/rc.d/${GATEWAY_SERVICE} <<'RCD'
#!/bin/sh
#
# PROVIDE: openclaw_gateway
# REQUIRE: LOGIN
# KEYWORD: shutdown
#
. /etc/rc.subr

name=\"openclaw_gateway\"
rcvar=\"openclaw_gateway_enable\"

load_rc_config \$name

: \${openclaw_gateway_enable:=\"NO\"}
: \${openclaw_gateway_user:=\"${OC_USER}\"}
: \${openclaw_gateway_pid:=\"/var/run/openclaw/openclaw_gateway.pid\"}

pidfile=\"\${openclaw_gateway_pid}\"

start_precmd=\"\${name}_prestart\"
start_cmd=\"\${name}_start\"
stop_cmd=\"\${name}_stop\"
status_cmd=\"\${name}_status\"

openclaw_gateway_prestart()
{
  install -d -m 0755 /var/run/openclaw
  chown \${openclaw_gateway_user}:\${openclaw_gateway_user} /var/run/openclaw 2>/dev/null || true

  install -d -m 0755 /var/log
  touch /var/log/openclaw_gateway.log
  chown \${openclaw_gateway_user}:\${openclaw_gateway_user} /var/log/openclaw_gateway.log 2>/dev/null || true
}

openclaw_gateway_start()
{
  echo \"Starting \${name} as \${openclaw_gateway_user}...\"
  su -m \"\${openclaw_gateway_user}\" -c \"/usr/local/libexec/openclaw-gateway-run\" || true

  if [ -f \"\${pidfile}\" ] && kill -0 \"\$(cat \"\${pidfile}\")\" 2>/dev/null; then
    echo \"\${name} started, pid \$(cat \"\${pidfile}\")\"
    return 0
  fi

  echo \"Failed to start \${name}. See /var/log/openclaw_gateway.log\"
  return 1
}

openclaw_gateway_stop()
{
  if [ ! -f \"\${pidfile}\" ]; then
    echo \"\${name} not running (no pidfile)\"
    return 0
  fi

  pid=\"\$(cat \"\${pidfile}\")\"
  if ! kill -0 \"\${pid}\" 2>/dev/null; then
    echo \"\${name} not running (stale pidfile)\"
    rm -f \"\${pidfile}\"
    return 0
  fi

  echo \"Stopping \${name} (pid \${pid})...\"
  kill \"\${pid}\" 2>/dev/null || true

  i=0
  while kill -0 \"\${pid}\" 2>/dev/null; do
    i=\$((i+1))
    [ \"\${i}\" -ge 20 ] && break
    sleep 0.5
  done

  if kill -0 \"\${pid}\" 2>/dev/null; then
    echo \"Still running; killing hard...\"
    kill -9 \"\${pid}\" 2>/dev/null || true
  fi

  rm -f \"\${pidfile}\"
  echo \"\${name} stopped.\"
}

openclaw_gateway_status()
{
  if [ -f \"\${pidfile}\" ] && kill -0 \"\$(cat \"\${pidfile}\")\" 2>/dev/null; then
    echo \"\${name} is running as pid \$(cat \"\${pidfile}\")\"
    return 0
  fi
  echo \"\${name} is not running.\"
  return 1
}

run_rc_command \"\$1\"
RCD
chmod 0555 /usr/local/etc/rc.d/${GATEWAY_SERVICE}"

  # enable + start
  jexec_sh "sysrc openclaw_gateway_enable=YES >/dev/null"
  jexec_sh "sysrc openclaw_gateway_user='${OC_USER}' >/dev/null"

  msg "Starting gateway…"
  jexec_sh "service ${GATEWAY_SERVICE} onestart >/dev/null 2>&1 || service ${GATEWAY_SERVICE} start >/dev/null 2>&1 || true"
}

summary() {
  TOKEN="$(jexec_sh "su - '$OC_USER' -c 'cat ~/.openclaw/gateway.token 2>/dev/null || true'" | tr -d '\r' | tail -n1)"
  msg "Done."
  echo ""
  echo "Jail:      ${JAIL_NAME}  (${JAIL_IP})"
  echo "User:      ${OC_USER}"
  echo "Port:      ${OC_PORT}"
  echo "Token:     ${TOKEN:-<missing>}"
  echo ""
  echo "Next:"
  echo "  - Ensure host forwarder is running:  doas service openclaw_forward start"
  echo "  - Open UI on host:                  http://127.0.0.1:${OC_PORT}/"
}

main() {
  msg "OpenClaw installer/repair (jail)"
  msg "Target jail: ${JAIL_NAME}"

  ensure_jail_running
  ensure_pkg_bootstrap
  ensure_user
  ensure_deps
  install_openclaw
  install_clipboard_stub
  write_token_and_config
  install_gateway_wrapper_and_service
  summary
}

main "$@"
