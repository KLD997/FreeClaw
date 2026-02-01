# OpenClaw on FreeBSD 15 - Complete Installation Guide

**Production-ready setup using VNET jails and pf forwarding**

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ FreeBSD 15 Host                                             │
│                                                             │
│  ┌─────────────────┐         ┌──────────────────┐         │
│  │ bridge0         │         │ pf Firewall      │         │
│  │ 10.30.0.1/24    │◄────────┤ NAT + rdr        │         │
│  └────────┬────────┘         └──────────────────┘         │
│           │                                                 │
│           │ epair0a                                        │
│  ┌────────▼────────────────────────────────────┐          │
│  │ Jail: openclaw (VNET)                       │          │
│  │ ┌──────────────────────────────────────┐   │          │
│  │ │ epair0b: 10.30.0.10/24               │   │          │
│  │ │ OpenClaw Gateway: 0.0.0.0:18789      │   │          │
│  │ │ User: kld (persistent ZFS datasets)   │   │          │
│  │ └──────────────────────────────────────┘   │          │
│  └─────────────────────────────────────────────┘          │
│                                                             │
│  Access: http://127.0.0.1:18789/ (via pf rdr)             │
└─────────────────────────────────────────────────────────────┘
```

**Key Design Decisions:**
- **VNET "thick" jail**: Complete network isolation with own IP stack
- **pf rdr forwarding**: Stable, boring, reliable (no socat/pidfile complexity)
- **ZFS datasets**: Persistent storage independent of jail lifecycle
- **User UID/GID matching**: Seamless file ownership between host/jail

---

## Package Requirements

### Host Packages

```sh
doas pkg install -y \
  jail \
  ezjail \
  sysrc \
  pf \
  git \
  zsh \
  bsddialog \
  nerd-fonts \
  node22 \
  npm-node22
```

**Package Breakdown:**

| Package | Purpose |
|---------|---------|
| `jail`, `ezjail` | Jail management infrastructure |
| `sysrc` | rc.conf manipulation |
| `pf` | Packet filter (NAT + port forwarding) |
| `git` | Version control for configs |
| `zsh` | Shell (TUI requires zsh) |
| `bsddialog` | TUI dialog library |
| `nerd-fonts` | Terminal icons (optional but recommended) |
| `node22`, `npm-node22` | JavaScript runtime for OpenClaw |

### Jail Packages

```sh
# Installed automatically by openclaw-freebsd-install.sh
pkg install -y \
  ca_root_nss \
  curl \
  git \
  jq \
  tmux \
  node22 \
  npm-node22
```

---

## Installation Steps

### 1. ZFS Dataset Structure

Create persistent datasets **before** building the jail:

```sh
# Jail root (can be destroyed/recreated)
doas zfs create -o mountpoint=/usr/jails zroot/usr/jails
doas zfs create -o mountpoint=/usr/jails/openclaw zroot/usr/jails/openclaw

# Persistent user home (configs, tokens, pairing data)
doas zfs create -o mountpoint=/usr/jails/openclaw/home zroot/usr/jails/openclaw/home

# Persistent workspace (where OpenClaw executes tasks)
doas zfs create \
  -o mountpoint=/usr/jails/openclaw/home/kld/ocDownloads \
  zroot/usr/jails/openclaw/home/kld/ocDownloads
```

**Rationale:** Jail root is ephemeral (can be nuked for upgrades), but user data persists across rebuilds.

---

### 2. Network Configuration

#### 2.1 Create bridge0

Add to `/etc/rc.conf`:

```conf
cloned_interfaces="bridge0"
ifconfig_bridge0="inet 10.30.0.1/24 up"
```

Activate:

```sh
doas service netif restart
```

Verify:

```sh
ifconfig bridge0
# Should show: inet 10.30.0.1 netmask 0xffffff00
```

#### 2.2 Jail Configuration

Create `/etc/jail.conf.d/openclaw.conf`:

```conf
openclaw {
  host.hostname = "openclaw";
  path = "/usr/jails/openclaw";
  persist;

  # VNET (virtual network stack)
  vnet;
  vnet.interface = "epair0b";

  # Network setup
  exec.prestart  = "ifconfig epair0 create up";
  exec.prestart += "ifconfig epair0a up";
  exec.prestart += "ifconfig bridge0 addm epair0a up";
  exec.prestart += "ifconfig epair0b vnet openclaw";

  # Startup/shutdown
  exec.start = "/bin/sh /etc/rc";
  exec.stop  = "/bin/sh /etc/rc.shutdown";

  # Cleanup
  exec.poststop  = "ifconfig bridge0 deletem epair0a || true";
  exec.poststop += "ifconfig epair0a destroy || true";

  # Security
  allow.raw_sockets = 0;
  allow.mount = 0;
  allow.mount.devfs = 1;
  devfs_ruleset = 4;
}
```

#### 2.3 Jail Network Settings

Inside jail's `/etc/rc.conf`:

```conf
ifconfig_epair0b="inet 10.30.0.10/24 up"
defaultrouter="10.30.0.1"
sshd_enable="YES"
```

---

### 3. Firewall Configuration (pf)

**CRITICAL:** The `set skip on lo0` directive **must be commented out** for `rdr on lo0` to work.

Create `/etc/pf.conf`:

```pf
# /etc/pf.conf
# OpenClaw jail setup with localhost forwarding

ext_if   = "rge0"        # Adjust to your LAN interface
ts_if    = "tailscale0"  # Optional: Tailscale interface
jail_if  = "bridge0"
jail_net = "10.30.0.0/24"

##### OPTIONS #####
set block-policy drop
# CRITICAL: Do NOT skip lo0 when using rdr on lo0
# set skip on lo0

##### NORMALIZATION #####
scrub in all

##### NAT/REDIRECTION #####

# NAT jail traffic to external interface
nat on $ext_if from $jail_net to any -> ($ext_if)

# Forward localhost:18789 to jail gateway
rdr pass on lo0 inet proto tcp from any to 127.0.0.1 port 18789 -> 10.30.0.10 port 18789

##### FILTERING #####

# Allow loopback (required when not using 'set skip on lo0')
pass quick on lo0 all

# Allow all traffic on jail bridge
pass quick on $jail_if all

# Default deny inbound
block in all

# Allow host outbound
pass out on $ext_if inet proto { tcp udp icmp } from ($ext_if) to any keep state

# Allow jail outbound: DNS + HTTP/HTTPS
pass out on $ext_if inet proto udp from $jail_net to any port 53 keep state
pass out on $ext_if inet proto tcp from $jail_net to any port { 80, 443 } flags S/SA keep state

##### OPTIONAL: Tailscale #####
pass in  on $ts_if all keep state
pass out on $ts_if all keep state
```

Enable and validate:

```sh
# Enable pf
doas sysrc pf_enable="YES"
doas sysrc pflog_enable="YES"

# Validate syntax
doas pfctl -nf /etc/pf.conf

# Load rules
doas service pf start

# Verify rdr rule exists
doas pfctl -sn | grep 18789
# Should show: rdr pass on lo0 inet proto tcp from any to 127.0.0.1 port = 18789 -> 10.30.0.10 port 18789
```

---

### 4. Jail Deployment

#### 4.1 Bootstrap Jail

```sh
# Start jail
doas service jail start openclaw

# Verify jail is running
doas jls
```

#### 4.2 Install OpenClaw (Automated)

Use the provided installer script:

```sh
chmod +x openclaw-freebsd-install.sh
doas ./openclaw-freebsd-install.sh
```

**What the installer does:**

1. Creates user `kld` with matching host UID/GID
2. Installs Node.js and dependencies
3. Installs OpenClaw via npm global
4. Creates clipboard stub (prevents FreeBSD startup crash)
5. Generates authentication token
6. Creates `/usr/local/etc/rc.d/openclaw_gateway` service
7. Starts gateway service

#### 4.3 Manual Installation (Alternative)

```sh
# Enter jail
doas jexec openclaw

# Bootstrap pkg
env ASSUME_ALWAYS_YES=YES pkg bootstrap

# Install dependencies
pkg install -y ca_root_nss curl git jq tmux node22 npm-node22

# Create user (match your host UID/GID)
pw groupadd -n kld -g 1001
pw useradd -n kld -u 1001 -g 1001 -m -s /bin/sh

# Install OpenClaw globally
npm install -g openclaw@latest

# Generate token
su - kld
mkdir -p ~/.openclaw
umask 077
openssl rand -hex 32 > ~/.openclaw/gateway.token

# Create config
cat > ~/.openclaw/openclaw.json <<'EOF'
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "YOUR_TOKEN_HERE"
    },
    "controlUi": {
      "enabled": true,
      "basePath": "/",
      "allowInsecureAuth": true
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/home/kld/ocDownloads"
    }
  }
}
EOF
```

---

### 5. Service Configuration

The installer creates `/usr/local/etc/rc.d/openclaw_gateway` with proper:

- PID management (`/var/run/openclaw/openclaw_gateway.pid`)
- Logging (`/var/log/openclaw_gateway.log`)
- User context (runs as `kld`)
- PATH configuration (ensures `node` is found)

Enable in jail's `/etc/rc.conf`:

```conf
openclaw_gateway_enable="YES"
openclaw_gateway_user="kld"
```

Service commands:

```sh
# Start
doas jexec openclaw service openclaw_gateway start

# Stop
doas jexec openclaw service openclaw_gateway stop

# Restart
doas jexec openclaw service openclaw_gateway restart

# Status
doas jexec openclaw service openclaw_gateway status

# View logs
doas jexec openclaw tail -f /var/log/openclaw_gateway.log
```

---

### 6. TUI Manager Installation

```sh
# Create directory
mkdir -p ~/.local/bin/openclaw

# Copy TUI script
cp openclaw-tui.zsh ~/.local/bin/openclaw/
chmod +x ~/.local/bin/openclaw/openclaw-tui.zsh

# Optional: Add to PATH
echo 'export PATH="$HOME/.local/bin/openclaw:$PATH"' >> ~/.zshrc
```

Launch:

```sh
~/.local/bin/openclaw/openclaw-tui.zsh
```

**TUI Features:**

- Install/repair OpenClaw
- Start/stop/restart stack
- View status and logs
- Open Web UI
- Edit configuration
- Manage API keys
- Run OpenClaw wizards (onboard, dashboard, configure)

---

## Verification & Testing

### 1. Check Network Stack

```sh
# Host: Verify bridge
ifconfig bridge0

# Host: Verify pf rules
doas pfctl -sn | grep 18789

# Jail: Verify IP configuration
doas jexec openclaw ifconfig epair0b

# Jail: Verify default route
doas jexec openclaw netstat -rn

# Jail: Test external connectivity
doas jexec openclaw fetch -qo- https://www.freebsd.org | head
```

### 2. Check Gateway Service

```sh
# Verify process is running
doas jexec openclaw ps aux | grep openclaw

# Verify listening on port
doas jexec openclaw sockstat -4l -P tcp | grep 18789
# Should show: kld      node       12345 *  tcp4   *:18789

# Check logs for errors
doas jexec openclaw tail -n 50 /var/log/openclaw_gateway.log
```

### 3. Test Web UI Access

```sh
# Test from host
fetch -qo- http://127.0.0.1:18789/ | head

# Or use curl
curl -I http://127.0.0.1:18789/
```

### 4. Full Stack Test

```sh
# Start everything
doas service jail start openclaw
doas jexec openclaw service openclaw_gateway start

# Check status
doas jls
doas jexec openclaw service openclaw_gateway status

# Open browser
firefox http://127.0.0.1:18789/
```

---

## Troubleshooting

### "No route to host" when accessing localhost:18789

**Cause:** pf is blocking loopback traffic.

**Fix:**

```sh
# Edit /etc/pf.conf
# Comment out: set skip on lo0
# Add: pass quick on lo0 all

doas pfctl -nf /etc/pf.conf  # Validate
doas service pf restart      # Apply
```

### "Connection refused" to localhost:18789

**Cause:** Gateway service not running or not listening.

**Debug:**

```sh
# Check service status
doas jexec openclaw service openclaw_gateway status

# Check listening ports
doas jexec openclaw sockstat -4l | grep 18789

# Check logs
doas jexec openclaw tail -n 100 /var/log/openclaw_gateway.log

# Test direct connection to jail IP
fetch -qo- http://10.30.0.10:18789/ | head
```

### Gateway fails to start with JSON parse error

**Symptoms:**

```
JSON5: invalid character ',' at line:col
```

**Fix:**

```sh
# Run OpenClaw doctor
doas jexec openclaw su - kld -c 'openclaw doctor --fix'

# Or manually edit config
doas jexec openclaw vi /home/kld/.openclaw/openclaw.json
```

### Jail won't start

**Debug:**

```sh
# Check jail configuration syntax
doas jail -c -f /etc/jail.conf.d/openclaw.conf openclaw

# View jail logs
doas tail -f /var/log/messages

# Check if bridge exists
ifconfig bridge0

# Manually create epair for testing
doas ifconfig epair create
```

### Gateway starts but crashes immediately

**Check for:**

1. **Missing clipboard module stub:**

```sh
doas jexec openclaw test -f /usr/local/lib/node_modules/openclaw/node_modules/@mariozechner/clipboard-freebsd-x64/index.js
echo $?  # Should be 0
```

2. **PATH issues:**

```sh
doas jexec openclaw su - kld -c 'which node'
# Should show: /usr/local/bin/node
```

3. **Permission issues:**

```sh
doas jexec openclaw ls -la /var/run/openclaw/
doas jexec openclaw ls -la /home/kld/.openclaw/
```

### Cannot access jail from host

**Test connectivity:**

```sh
# Ping jail from host
ping -c 3 10.30.0.10

# Check pf NAT rules
doas pfctl -sn

# Check firewall state
doas pfctl -ss | grep 10.30.0.10
```

---

## Security Considerations

### 1. Authentication

The default setup uses token authentication. Retrieve your token:

```sh
doas jexec openclaw su - kld -c 'cat ~/.openclaw/gateway.token'
```

**Important:** Keep this token secure. Anyone with the token has full access to OpenClaw.

### 2. Network Exposure

**Current setup:** Web UI accessible only via `127.0.0.1` (localhost).

**To expose remotely (use with caution):**

```sh
# SSH tunnel (recommended)
ssh -L 18789:127.0.0.1:18789 yourhost

# Or add pf rdr on external interface (NOT recommended without TLS)
# rdr pass on $ext_if proto tcp from any to ($ext_if) port 18789 -> 10.30.0.10 port 18789
```

### 3. Workspace Isolation

Limit OpenClaw's file access:

```json
{
  "agents": {
    "defaults": {
      "workspace": "/home/kld/ocDownloads"
    }
  }
}
```

**Do NOT mount:**
- `/etc` (host system configuration)
- `/usr/local/etc` (application configs)
- `~/.ssh` (SSH keys)
- Root filesystem

### 4. Jail Hardening

Additional jail.conf options:

```conf
# Disable raw sockets
allow.raw_sockets = 0;

# Disable mounting
allow.mount = 0;
allow.mount.devfs = 1;  # But allow devfs

# Limit sysctls
allow.sysvipc = 0;

# Security flags
enforce_statfs = 2;
```

---

## Advanced Configuration

### Tailscale Access (Optional)

**Option 1: Tailscale on host only (recommended)**

Access via SSH tunnel:

```sh
ssh -L 18789:127.0.0.1:18789 yourhost.tail-scale.ts.net
```

**Option 2: Expose via Tailscale pf rule (requires careful auth)**

Add to `/etc/pf.conf`:

```pf
# WARNING: Exposes UI to entire tailnet
rdr pass on $ts_if proto tcp from any to ($ts_if) port 18789 -> 10.30.0.10 port 18789
```

**Option 3: Tailscale inside jail**

Only if you need the jail to have its own tailnet identity:

```sh
doas jexec openclaw pkg install -y tailscale
doas jexec openclaw sysrc tailscaled_enable="YES"
doas jexec openclaw service tailscaled start
doas jexec openclaw tailscale up
```

### Multiple Jails

Modify for additional instances:

```conf
# /etc/jail.conf.d/openclaw2.conf
openclaw2 {
  host.hostname = "openclaw2";
  path = "/usr/jails/openclaw2";
  vnet.interface = "epair1b";
  # Change epair number, IP, etc.
}
```

Update pf:

```pf
rdr pass on lo0 proto tcp from any to 127.0.0.1 port 18790 -> 10.30.0.11 port 18789
```

---

## File Locations Reference

| Path | Purpose |
|------|---------|
| `/etc/jail.conf.d/openclaw.conf` | Jail configuration |
| `/etc/pf.conf` | Firewall rules |
| `/usr/jails/openclaw` | Jail root (ephemeral) |
| `/usr/jails/openclaw/home` | Persistent user data |
| `/home/kld/.openclaw/openclaw.json` | OpenClaw config (in jail) |
| `/home/kld/.openclaw/gateway.token` | Auth token (in jail) |
| `/home/kld/.openclaw/.env` | API keys (in jail) |
| `/var/log/openclaw_gateway.log` | Gateway logs (in jail) |
| `/var/run/openclaw/openclaw_gateway.pid` | Service PID (in jail) |
| `/usr/local/etc/rc.d/openclaw_gateway` | rc.d service script (in jail) |

---

## Quick Command Reference

```sh
# Start stack
doas service jail start openclaw
doas jexec openclaw service openclaw_gateway start

# Stop stack
doas jexec openclaw service openclaw_gateway stop
doas service jail stop openclaw

# Restart gateway only
doas jexec openclaw service openclaw_gateway restart

# View logs
doas jexec openclaw tail -f /var/log/openclaw_gateway.log

# Enter jail
doas jexec openclaw

# Execute as jail user
doas jexec openclaw su - kld

# Check status
doas jls
doas jexec openclaw service openclaw_gateway status
doas pfctl -sn | grep 18789

# Reload pf rules
doas pfctl -f /etc/pf.conf

# Test UI
fetch -qo- http://127.0.0.1:18789/ | head
```

---

## Upgrade Procedure

### OpenClaw Upgrade

```sh
# Stop gateway
doas jexec openclaw service openclaw_gateway stop

# Upgrade via npm
doas jexec openclaw npm update -g openclaw

# Start gateway
doas jexec openclaw service openclaw_gateway start
```

### Jail Rebuild (preserves user data)

```sh
# Stop jail
doas service jail stop openclaw

# Destroy jail root (ZFS datasets persist)
doas zfs destroy zroot/usr/jails/openclaw

# Recreate and populate
doas zfs create -o mountpoint=/usr/jails/openclaw zroot/usr/jails/openclaw
# ... run base extraction/pkg install ...

# User data automatically available at /usr/jails/openclaw/home
```

---

## License & Credits

- **OpenClaw**: Check upstream project for licensing
- **FreeBSD**: BSD License
- **bsddialog**: BSD-3-Clause License

---

## Support & Resources

- OpenClaw Documentation: Check upstream project
- FreeBSD Handbook: https://docs.freebsd.org/
- FreeBSD Jails: https://docs.freebsd.org/en/books/handbook/jails/
- pf Firewall: https://www.freebsd.org/doc/handbook/firewalls-pf.html

---

**Last Updated:** 2025-02-01  
**FreeBSD Version:** 15.0  
**OpenClaw Version:** Latest (npm)
