# OpenClaw FreeBSD Complete Installation Guide

**Production deployment with VNET jails, socat forwarding, and persistent storage**

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Host System Setup](#host-system-setup)
4. [Jail Configuration](#jail-configuration)
5. [OpenClaw Installation](#openclaw-installation)
6. [Service Configuration](#service-configuration)
7. [Testing & Verification](#testing--verification)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Packages

```sh
# Install on host system
doas pkg install -y \
  jail \
  sysrc \
  pf \
  socat \
  git \
  zsh \
  bsddialog \
  node22 \
  nerd-fonts \
  npm-node22
```

### System Requirements

- FreeBSD 15.0 or later
- ZFS filesystem (recommended)
- Root/doas access
- 5GB+ free disk space
- Network connectivity

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────┐
│ FreeBSD 15 Host                                            │
│                                                            │
│  ┌──────────────┐        ┌─────────────────────┐           │
│  │ 127.0.0.1    │        │ socat (openclaw_    │           │
│  │ :18789       │◄───────┤  forward service)   │           │
│  └──────────────┘        └──────────┬──────────┘           │
│                                     │                      │
│  ┌──────────────┐        ┌──────────▼──────────┐           │
│  │ bridge0      │        │ pf Firewall         │           │
│  │ 10.30.0.1/24 │◄───────┤ NAT + filtering     │           │
│  └──────┬───────┘        └─────────────────────┘           │
│         │                                                  │
│         │ epair0a                                          │
│  ┌──────▼──────────────────────────────────────┐           │
│  │ Jail: openclaw (VNET)                       │           │
│  │ ┌────────────────────────────────────────┐  │           │
│  │ │ epair0b: 10.30.0.10/24                 │  │           │
│  │ │ OpenClaw Gateway: 0.0.0.0:18789        │  │           │
│  │ │ User: <your-username>                  │  │           │
│  │ │ Persistent: ZFS datasets + nullfs      │  │           │
│  │ └────────────────────────────────────────┘  │           │
│  └─────────────────────────────────────────────┘           │
│                                                            │
│  Access: http://127.0.0.1:18789/ (via socat)               │
└────────────────────────────────────────────────────────────┘
```

**Design Decisions:**

- **VNET jail:** Complete network isolation
- **socat forwarding:** Localhost → jail (handles state properly)
- **ZFS datasets:** Persistent storage independent of jail
- **nullfs mounts:** Shared directories between host and jail

---

## Host System Setup

### Step 1: Create ZFS Datasets
```
doas zfs create -o mountpoint=/usr/jails -o atime=0 -o compressions=zstd zroot/usr/jails
doas zfs create -o mountpoint=/usr/jails/openclaw -o atime=0 -o compressions=zstd zroot/usr/jails/openclaw
```
#### If running on localhost, I strongly recommemend setting a storage quota
```
doas zfs set quota=50G zroot/usr/jail/openclaw
```

If you want to give your openclaw a shared space, create a dataset on the host
```
doas zfs create -o mountpoint=/PATH/TO/SHARED/DIRECTORY -o atime=0 compression=zstd zroot/usr/jail/openclaw/PATH/TO/SHARED/DIRECTORY
```

### Step 2: Configure Network (bridge0)

Add to `/etc/rc.conf`:

```
doas sysrc cloned_interfaces+="bridge0"
doas sysrc ifconfig_bridge0="inet 10.30.0.1/24 up"
```
Reboot, it should now be visible in ifconfig. 
```
ifconfig bridge0
# Should show: inet 10.30.0.1 netmask 0xffffff00
```

### Step 3: Configure Firewall (pf)

**IMPORTANT:** Update interface names in pf.conf before using!

Create `/etc/pf.conf`:

```
# /etc/pf.conf

ext_if   = "rge0"           # CHANGE THIS: Your WAN interface (ifconfig to check)
ts_if    = "tailscale0"     # Optional: Tailscale interface (if using)
jail_if  = "bridge0"
jail_net = "10.30.0.0/24"   

# Host-side jail gateway IP (bridge0 IP on host)
host_jail_ip = "10.30.0.1"

# OpenClaw in jail
openclaw_ip   = "10.30.0.10" # Change this to your openclaws jail IP. Check /etc/jail.conf.d/openclaw.conf
openclaw_port = "18789" # Default Openclaw port

##### OPTIONS
set block-policy drop
set state-policy floating

##### NORMALIZATION
scrub in all

##### TRANSLATION

# NAT jail traffic out to WAN
nat on $ext_if from $jail_net to any -> ($ext_if)

# NOTE: localhost -> jail forwarding handled by socat (openclaw_forward service)
# pf rdr+nat across interfaces doesn't track state properly

##### FILTERING

block in all

# Loopback — allow all (includes rdr entry point)
pass quick on lo0 all

# Bridge — allow all host<->jail traffic unconditionally
pass quick on $jail_if all

# Host outbound (WAN)
pass out on $ext_if inet proto { tcp udp icmp } from ($ext_if) to any keep state

# Jail outbound: DNS, HTTP, HTTPS
pass out on $ext_if inet proto udp from $jail_net to any port 53 keep state
pass out on $ext_if inet proto tcp from $jail_net to any port { 80 443 } keep state

##### Tailscale (optional - remove if not using)
pass in  on $ts_if all keep state
pass out on $ts_if all keep state

pass in  on $ts_if proto { tcp udp } to ($ts_if) port $kdeconnect_ports keep state
pass out on $ts_if proto { tcp udp } from ($ts_if) port $kdeconnect_ports keep state
```

Enable and load pf:

```
doas sysrc pf_enable="YES"
doas sysrc pflog_enable="YES"

# Validate syntax
doas pfctl -nf /etc/pf.conf

# Load rules
doas service pf start
```
--- 

## Jail Configuration

### Step 6: Create Jail fstab

Create `/etc/jail.fstab.openclaw`:

```
# Allow access to shared data directory
/PATH/TO/SHARED/DIRECTORY	/usr/jails/openclaw/PATH/TO/SHARED/DIRECTORY

# Allow request to elevated privileged commands
/var/run/openclaw-requests	/usr/jails/openclaw/var/run/openclaw-requests	nullfs	rw,noatime	0	0
EOF
```

### Step 7: Create Jail Configuration

Create `/etc/jail.conf.d/openclaw.conf`:

```
doas mkdir -p /etc/jail.conf.d

doas tee /etc/jail.conf.d/openclaw.conf <<'EOF'
# /etc/jail.conf.d/openclaw.conf

openclaw {
  host.hostname = "openclaw.local";
  path = "/usr/jails/openclaw";

  # nullfs mounts (shared directories)
  mount.fstab = "/etc/jail.fstab.openclaw";

  # Keep /dev minimal
  # devfs_ruleset = 45;  # Optional: custom devfs rules

  # Bring up networking inside the jail
  exec.start += "/sbin/ifconfig lo0 127.0.0.1 up";
  exec.start += "/sbin/ifconfig ${name}b 10.30.0.10/24 up";
  exec.start += "/sbin/route add default 10.30.0.1";
}
EOF
```

Enable jails in `/etc/rc.conf`:

```sh
doas sysrc jail_enable="YES"
doas sysrc jail_conf="/etc/jail.conf.d/*.conf"
```

### Step 8: Install Jail

```
doas bsdinstall jail /usr/jails/openclaw
```

Copy DNS configuration:

```
doas cp /etc/resolv.conf /usr/jails/openclaw/etc/
```

Create mount points inside jail:

```
doas mkdir -p /usr/jails/openclaw/PATH/TO/SHARED/DIRECTORY
doas mkdir -p /usr/jails/openclaw/var/run/openclaw-requests
```

Start the jail:

```
doas service jail start openclaw
```

Verify:

```
doas jls
```
```
doas jexec openclaw ifconfig
```
---

## OpenClaw Installation

### Step 9: Run Automated Installer

Download the installer script (or use the one provided):

```
chmod +x openclaw-freebsd-install.sh
doas ./openclaw-freebsd-install.sh
```

The installer will:
1. Prompt for your username #note this needs to be your current username. run `id` in your terminal.
2. Install Node.js and dependencies in jail
3. Install OpenClaw globally
4. Create jail gateway service
5. Generate authentication token
6. Configure and start the jail gateway
7. **Install and configure host socat forwarding service**
8. **Start the socat forwarder**

**What the installer creates:**

**In the jail:**
- `/usr/local/etc/rc.d/openclaw_gateway` (gateway service)
- `/usr/local/libexec/openclaw-gateway-run` (gateway wrapper)
- `/home/<user>/.openclaw/openclaw.json` (config)
- `/home/<user>/.openclaw/gateway.token` (auth token)

**On the host:**
- `/usr/local/etc/rc.d/openclaw_forward` (socat forwarding service)
- Enables and starts the forwarder automatically

**Manual Installation Alternative:**

If you prefer to install manually, see [Manual Installation Steps](#manual-installation-alternative) below.

---

## Service Configuration

### Step 10: Verify Jail Gateway Service

The installer creates `/usr/local/etc/rc.d/openclaw_gateway` inside the jail.

Check it's running:
```
doas jexec openclaw service openclaw_gateway status
```

If not running, start it:
```
doas jexec openclaw service openclaw_gateway start
```

View logs:
```
doas jexec openclaw tail -f /var/log/openclaw_gateway.log
```

### Step 10: Verify Host Forwarding Service

The socat forwarder should already be running:
```
doas service openclaw_forward status
```

If it's not running (manual installation), start it:
```
doas service openclaw_forward start
```

Verify:
```
doas service openclaw_forward status
```

Check logs:
```
doas tail -f /var/log/openclaw_forward.log
```

---

## Testing & Verification

### Network Stack Test
```
# Host: Verify bridge
ifconfig bridge0

# Host: Verify pf NAT rules
doas pfctl -sn

# Jail: Verify IP configuration
doas jexec openclaw ifconfig

# Jail: Test default route
doas jexec openclaw netstat -rn

# Jail: Test external connectivity
doas jexec openclaw fetch -qo- https://www.freebsd.org | head
```

### Gateway Service Test
```
# Jail: Check process
doas jexec openclaw ps aux | grep openclaw

# Jail: Check listening port
doas jexec openclaw sockstat -4l | grep 18789
# Should show: <user>  node  <pid>  *  tcp4  *:18789

# Host: Test socat forwarding
fetch -qo- http://127.0.0.1:18789/ | head
```

### Retrieve Authentication Token
```
USERNAME="your-username"  # Change this!

doas jexec openclaw su - ${USERNAME} -c 'cat ~/.openclaw/gateway.token'
```

### Access Web UI

Open your browser to:
```
http://127.0.0.1:18789/
```

Enter the token when prompted.

---

## Troubleshooting

### "Connection refused" to localhost:18789

**Possible causes:**

1. **socat not running:**
   ```sh
   doas service openclaw_forward status
   doas service openclaw_forward start
   ```

2. **Jail gateway not running:**
   ```sh
   doas jexec openclaw service openclaw_gateway status
   doas jexec openclaw service openclaw_gateway start
   ```

3. **Check logs:**
   ```sh
   # Socat logs
   doas tail -f /var/log/openclaw_forward.log
   
   # Gateway logs (in jail)
   doas jexec openclaw tail -f /var/log/openclaw_gateway.log
   ```

### Jail won't start

**Debug steps:**

```sh
# Try manual start
doas jail -c -f /etc/jail.conf.d/openclaw.conf openclaw

# Check system logs
doas tail -f /var/log/messages

# Verify bridge exists
ifconfig bridge0

# Check fstab syntax
cat /etc/jail.fstab.openclaw
```

### Gateway crashes on startup

**Check for clipboard module issue:**

```sh
doas jexec openclaw test -f \
  /usr/local/lib/node_modules/openclaw/node_modules/@mariozechner/clipboard-freebsd-x64/index.js

echo $?  # Should be 0
```

If missing, the installer should have created a stub. Re-run the installer or create manually.

### "No route to host" from jail

**Fix pf blocking:**

```sh
# Verify pf allows jail traffic
doas pfctl -sr | grep bridge0

# Should see: pass quick on bridge0 all
```

**Test jail connectivity:**

```sh
# From jail, ping gateway
doas jexec openclaw ping -c 3 10.30.0.1

# From jail, test DNS
doas jexec openclaw nslookup freebsd.org
```

### socat keeps dying

**Check for port conflicts:**

```sh
# On host, check if something else is using port 18789
sockstat -4l | grep 18789
```

**Review socat logs:**

```sh
doas tail -n 100 /var/log/openclaw_forward.log
```

**Common issue:** socat dies if jail gateway isn't running yet. Start order:
1. Start jail
2. Start jail gateway service
3. Start host socat forwarding

---

## Manual Installation Alternative

If you prefer not to use the automated installer:

### Inside the Jail

```sh
# Enter jail
doas jexec openclaw

# Bootstrap pkg
env ASSUME_ALWAYS_YES=YES pkg bootstrap

# Install dependencies
pkg install -y ca_root_nss curl git jq tmux node22 npm-node22

# Create user (match your host username and UID/GID)
USERNAME="your-username"
UID="1001"  # Check with: id -u $USERNAME on host
GID="1001"  # Check with: id -g $USERNAME on host

pw groupadd -n ${USERNAME} -g ${GID}
pw useradd -n ${USERNAME} -u ${UID} -g ${GID} -m -s /bin/sh

# Install OpenClaw
npm install -g openclaw@latest

# Switch to user
su - ${USERNAME}

# Generate token
mkdir -p ~/.openclaw
umask 077
openssl rand -hex 32 > ~/.openclaw/gateway.token

# Create config
cat > ~/.openclaw/openclaw.json <<'JSON'
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "PASTE_YOUR_TOKEN_HERE"
    },
    "controlUi": {
      "enabled": true,
      "basePath": "/",
      "allowInsecureAuth": true
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/home/your-username/ocDownloads"
    }
  }
}
JSON

chmod 600 ~/.openclaw/openclaw.json

# Create env file for API keys
touch ~/.openclaw/.env
chmod 600 ~/.openclaw/.env
```

### Install Gateway Service (in jail)

Create `/usr/local/libexec/openclaw-gateway-run` inside jail:

```sh
# As root in jail
cat > /usr/local/libexec/openclaw-gateway-run <<'SH'
#!/bin/sh
set -eu

USER="your-username"  # Change this!
PIDFILE="/var/run/openclaw/openclaw_gateway.pid"
LOG="/var/log/openclaw_gateway.log"

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
export HOME="/home/${USER}"

mkdir -p /var/run/openclaw /var/log
chown -R "${USER}:${USER}" /var/run/openclaw /var/log 2>/dev/null || true
touch "$LOG"
chown "${USER}:${USER}" "$LOG" 2>/dev/null || true

command -v node >/dev/null 2>&1 || { echo "node not found in PATH=$PATH" >> "$LOG"; exit 1; }

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  exit 0
fi

/usr/local/bin/openclaw gateway >> "$LOG" 2>&1 &
echo $! > "$PIDFILE"

sleep 0.2
kill -0 "$(cat "$PIDFILE")" 2>/dev/null
SH

chmod 0555 /usr/local/libexec/openclaw-gateway-run
```

Copy the `openclaw_gateway` rc.d script to `/usr/local/etc/rc.d/openclaw_gateway` (update username in the script).

Enable and start:

```sh
# In jail's /etc/rc.conf
sysrc openclaw_gateway_enable="YES"
sysrc openclaw_gateway_user="your-username"

service openclaw_gateway start
```

---

## Post-Installation

### Add API Keys

```sh
# Enter jail as your user
doas jexec openclaw su - your-username

# Edit .env file
vi ~/.openclaw/.env

# Add your keys:
ANTHROPIC_API_KEY=sk-ant-xxx
OPENAI_API_KEY=sk-xxx
```

### Run Onboarding Wizard

```sh
doas jexec openclaw su - your-username -c 'openclaw onboard'
```

### Access Dashboard

```sh
doas jexec openclaw su - your-username -c 'openclaw dashboard'
```

---

## File Locations Reference

| Path | Purpose | Location |
|------|---------|----------|
| `/etc/pf.conf` | Firewall rules | Host |
| `/etc/jail.conf.d/openclaw.conf` | Jail configuration | Host |
| `/etc/jail.fstab.openclaw` | Jail nullfs mounts | Host |
| `/usr/local/etc/rc.d/openclaw_forward` | socat forwarding service | Host |
| `/var/log/openclaw_forward.log` | socat logs | Host |
| `/usr/jails/openclaw` | Jail root | Host |
| `/home/<user>/ocDownloads` | Shared workspace | Host (nullfs) |
| `/usr/jails/openclaw/usr/local/etc/rc.d/openclaw_gateway` | Gateway service | Jail (host path) |
| `/usr/local/etc/rc.d/openclaw_gateway` | Gateway service | Jail (jail path) |
| `/var/log/openclaw_gateway.log` | Gateway logs | Jail |
| `/home/<user>/.openclaw/openclaw.json` | OpenClaw config | Jail |
| `/home/<user>/.openclaw/gateway.token` | Auth token | Jail |
| `/home/<user>/.openclaw/.env` | API keys | Jail |

---

## Quick Command Reference

```sh
# Start everything
doas service jail start openclaw
doas jexec openclaw service openclaw_gateway start
doas service openclaw_forward start

# Stop everything
doas service openclaw_forward stop
doas jexec openclaw service openclaw_gateway stop
doas service jail stop openclaw

# Restart gateway only
doas jexec openclaw service openclaw_gateway restart

# Restart socat only
doas service openclaw_forward restart

# View logs
doas tail -f /var/log/openclaw_forward.log          # Host socat
doas jexec openclaw tail -f /var/log/openclaw_gateway.log  # Jail gateway

# Enter jail
doas jexec openclaw

# Execute as jail user
doas jexec openclaw su - your-username

# Check status
doas jls                                            # Jail status
doas service openclaw_forward status                # Host forwarder
doas jexec openclaw service openclaw_gateway status # Jail gateway
doas pfctl -sn | grep 18789                         # pf NAT rules
```

---

## Security Considerations

1. **Token Security:** Keep `gateway.token` secret
2. **Localhost Only:** Web UI only accessible via 127.0.0.1
3. **Workspace Isolation:** Limit OpenClaw to `ocDownloads` directory
4. **API Keys:** Store in `.env`, never commit to git
5. **Firewall:** Only allow necessary outbound ports (53, 80, 443)

---

## Maintenance

### Upgrade OpenClaw

```sh
doas jexec openclaw service openclaw_gateway stop
doas jexec openclaw npm update -g openclaw
doas jexec openclaw service openclaw_gateway start
```

### Rebuild Jail (preserves data)

```sh
# Stop services
doas service openclaw_forward stop
doas jexec openclaw service openclaw_gateway stop
doas service jail stop openclaw

# Destroy jail root (ZFS datasets persist!)
doas zfs destroy zroot/usr/jails/openclaw

# Recreate and re-extract base
doas zfs create -o mountpoint=/usr/jails/openclaw zroot/usr/jails/openclaw
doas tar -xf /usr/freebsd-dist/base.txz -C /usr/jails/openclaw

# Re-run installer
doas ./openclaw-freebsd-install.sh
```

### Backup Important Data

```sh
# Backup OpenClaw config and tokens
doas jexec openclaw tar -czf /tmp/openclaw-backup.tar.gz \
  /home/your-username/.openclaw

# Copy out of jail
doas cp /usr/jails/openclaw/tmp/openclaw-backup.tar.gz ~/backups/
```

---

**Last Updated:** 2025-02-01  
**FreeBSD Version:** 15.0  
**Tested Configuration:** ASRock B650M, AMD Ryzen 5 7600, 32GB RAM
