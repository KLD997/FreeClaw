# OpenClaw FreeBSD - Quick Start Guide

**Get OpenClaw running on FreeBSD 15 in under 30 minutes**

---

## Prerequisites

- FreeBSD 15.0 host system
- Root/doas access
- ZFS filesystem (recommended)
- Internet connection

---

## Quick Install (Copy-Paste Method)

### Step 1: Install Host Packages (2 minutes)

```sh
doas pkg install -y jail ezjail sysrc pf git zsh bsddialog nerd-fonts node22 npm-node22
```

### Step 2: Create ZFS Datasets (1 minute)

```sh
doas zfs create -o mountpoint=/usr/jails zroot/usr/jails
doas zfs create -o mountpoint=/usr/jails/openclaw zroot/usr/jails/openclaw
doas zfs create -o mountpoint=/usr/jails/openclaw/home zroot/usr/jails/openclaw/home
doas zfs create -o mountpoint=/usr/jails/openclaw/home/kld/ocDownloads zroot/usr/jails/openclaw/home/kld/ocDownloads
```

### Step 3: Configure Network (2 minutes)

Add to `/etc/rc.conf`:

```sh
doas sysrc cloned_interfaces+="bridge0"
doas sysrc ifconfig_bridge0="inet 10.30.0.1/24 up"
doas service netif restart
```

### Step 4: Configure Jail (3 minutes)

Create `/etc/jail.conf.d/openclaw.conf`:

```sh
cat <<'EOF' | doas tee /etc/jail.conf.d/openclaw.conf
openclaw {
  host.hostname = "openclaw";
  path = "/usr/jails/openclaw";
  persist;
  vnet;
  vnet.interface = "epair0b";
  exec.prestart  = "ifconfig epair0 create up";
  exec.prestart += "ifconfig epair0a up";
  exec.prestart += "ifconfig bridge0 addm epair0a up";
  exec.prestart += "ifconfig epair0b vnet openclaw";
  exec.start = "/bin/sh /etc/rc";
  exec.stop  = "/bin/sh /etc/rc.shutdown";
  exec.poststop  = "ifconfig bridge0 deletem epair0a || true";
  exec.poststop += "ifconfig epair0a destroy || true";
  allow.raw_sockets = 0;
  allow.mount = 0;
  allow.mount.devfs = 1;
  devfs_ruleset = 4;
}
EOF
```

### Step 5: Configure Firewall (3 minutes)

Create `/etc/pf.conf`:

```sh
cat <<'EOF' | doas tee /etc/pf.conf
ext_if   = "rge0"  # CHANGE THIS to your interface (run: ifconfig)
jail_if  = "bridge0"
jail_net = "10.30.0.0/24"

set block-policy drop
scrub in all

nat on $ext_if from $jail_net to any -> ($ext_if)
rdr pass on lo0 inet proto tcp from any to 127.0.0.1 port 18789 -> 10.30.0.10 port 18789

pass quick on lo0 all
pass quick on $jail_if all
block in all
pass out on $ext_if inet proto { tcp udp icmp } from ($ext_if) to any keep state
pass out on $ext_if inet proto udp from $jail_net to any port 53 keep state
pass out on $ext_if inet proto tcp from $jail_net to any port { 80, 443 } flags S/SA keep state
EOF
```

Enable pf:

```sh
doas sysrc pf_enable="YES"
doas pfctl -nf /etc/pf.conf  # Validate
doas service pf start
```

### Step 6: Bootstrap Jail (2 minutes)

```sh
# Extract FreeBSD base
doas tar -xf /usr/freebsd-dist/base.txz -C /usr/jails/openclaw

# Copy resolv.conf
doas cp /etc/resolv.conf /usr/jails/openclaw/etc/

# Configure jail network
cat <<'EOF' | doas tee /usr/jails/openclaw/etc/rc.conf
ifconfig_epair0b="inet 10.30.0.10/24 up"
defaultrouter="10.30.0.1"
sshd_enable="NO"
EOF

# Start jail
doas service jail start openclaw
```

### Step 7: Run Automated Installer (5 minutes)

Download and run the installer:

```sh
# Make sure you have openclaw-freebsd-install.sh in current directory
chmod +x openclaw-freebsd-install.sh
doas ./openclaw-freebsd-install.sh
```

The installer will:
- Create user `kld`
- Install Node.js and dependencies
- Install OpenClaw
- Configure and start the gateway service
- Display your authentication token

### Step 8: Access Web UI (1 minute)

```sh
# Open browser to
open http://127.0.0.1:18789/

# Or use command line
fetch -qo- http://127.0.0.1:18789/ | head
```

---

## Verify Installation

### Check Services

```sh
# Jail running?
doas jls

# Gateway running?
doas jexec openclaw service openclaw_gateway status

# Firewall rules loaded?
doas pfctl -sn | grep 18789

# UI accessible?
curl -I http://127.0.0.1:18789/
```

### Get Your Token

```sh
doas jexec openclaw su - kld -c 'cat ~/.openclaw/gateway.token'
```

---

## Install TUI Manager (Optional)

```sh
mkdir -p ~/.local/bin/openclaw
cp openclaw-tui.zsh ~/.local/bin/openclaw/
chmod +x ~/.local/bin/openclaw/openclaw-tui.zsh

# Run TUI
~/.local/bin/openclaw/openclaw-tui.zsh
```

---

## Common Post-Install Tasks

### Add API Keys

```sh
doas jexec openclaw su - kld

# Edit .env file
vi ~/.openclaw/.env

# Add your keys:
ANTHROPIC_API_KEY=sk-ant-xxx
OPENAI_API_KEY=sk-xxx
```

### Run Onboarding Wizard

```sh
doas jexec openclaw su - kld -c 'openclaw onboard'
```

### Access Dashboard

```sh
doas jexec openclaw su - kld -c 'openclaw dashboard'
```

---

## Quick Troubleshooting

### UI returns "No route to host"

Fix pf loopback blocking:

```sh
# Edit /etc/pf.conf
# Ensure these lines exist:
# pass quick on lo0 all
# (and that 'set skip on lo0' is commented out)

doas service pf restart
```

### Gateway won't start

Check logs:

```sh
doas jexec openclaw tail -f /var/log/openclaw_gateway.log
```

Fix common issues:

```sh
# Run doctor
doas jexec openclaw su - kld -c 'openclaw doctor --fix'
```

### Jail won't start

Check configuration:

```sh
doas jail -c -f /etc/jail.conf.d/openclaw.conf openclaw
```

Verify bridge exists:

```sh
ifconfig bridge0
```

---

## Daily Operations

### Start Everything

```sh
doas service jail start openclaw
doas jexec openclaw service openclaw_gateway start
```

### Stop Everything

```sh
doas jexec openclaw service openclaw_gateway stop
doas service jail stop openclaw
```

### Restart Gateway Only

```sh
doas jexec openclaw service openclaw_gateway restart
```

### View Logs

```sh
doas jexec openclaw tail -f /var/log/openclaw_gateway.log
```

---

## Next Steps

1. **Configure API Keys:** Add your Anthropic/OpenAI keys to `~/.openclaw/.env`
2. **Run Onboarding:** `openclaw onboard` to set up your first agent
3. **Explore Dashboard:** `openclaw dashboard` for monitoring
4. **Read Full Guide:** See `openclaw-freebsd-complete-guide.md` for advanced configuration

---

## Resource Links

- Full Installation Guide: `openclaw-freebsd-complete-guide.md`
- Package Reference: `openclaw-freebsd-packages.md`
- FreeBSD Handbook: https://docs.freebsd.org/
- OpenClaw Docs: Check upstream project

---

## Uninstall

```sh
# Stop and remove jail
doas service jail stop openclaw
doas service jail disable openclaw

# Destroy ZFS datasets (CAUTION: Deletes all data!)
doas zfs destroy -r zroot/usr/jails/openclaw

# Remove pf rules
doas vi /etc/pf.conf  # Remove openclaw sections
doas service pf reload

# Remove bridge
doas sysrc cloned_interfaces-="bridge0"
doas ifconfig bridge0 destroy
```

---

**Installation Time:** ~15-30 minutes  
**Difficulty:** Intermediate  
**Last Updated:** 2025-02-01
