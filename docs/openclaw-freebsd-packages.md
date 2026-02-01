# OpenClaw FreeBSD 15 - Package Requirements

## Host System Packages

Required packages for the FreeBSD 15 host system:

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

### Package Breakdown

| Package | Category | Purpose | Required |
|---------|----------|---------|----------|
| `jail` | Infrastructure | Base jail system | Yes |
| `ezjail` | Infrastructure | Simplified jail management | Yes |
| `sysrc` | Utilities | rc.conf manipulation | Yes |
| `pf` | Networking | Packet filter (NAT + forwarding) | Yes |
| `git` | Development | Version control | Recommended |
| `zsh` | Shell | Required for TUI script | Yes (for TUI) |
| `bsddialog` | UI | Dialog library for TUI | Yes (for TUI) |
| `nerd-fonts` | UI | Terminal icons/symbols | Recommended |
| `node22` | Runtime | JavaScript runtime | Yes |
| `npm-node22` | Runtime | Node package manager | Yes |

### Optional Host Packages

```sh
# Development tools
doas pkg install -y vim tmux htop

# Web browser (for UI access)
doas pkg install -y firefox chromium

# Tailscale (for remote access)
doas pkg install -y tailscale
```

---

## Jail Packages

Packages installed inside the OpenClaw jail:

```sh
pkg install -y \
  ca_root_nss \
  curl \
  git \
  jq \
  tmux \
  node22 \
  npm-node22
```

### Package Breakdown

| Package | Purpose | Required |
|---------|---------|----------|
| `ca_root_nss` | SSL/TLS certificate bundle | Yes |
| `curl` | HTTP client for debugging | Recommended |
| `git` | Version control (if needed in jail) | Optional |
| `jq` | JSON processing | Recommended |
| `tmux` | Terminal multiplexer | Optional |
| `node22` | JavaScript runtime | Yes |
| `npm-node22` | Node package manager | Yes |

### NPM Global Package

```sh
# Installed via npm inside jail
npm install -g openclaw@latest
```

---

## Minimum System Requirements

### Hardware

- **CPU:** Any modern x86_64 processor (AMD64)
- **RAM:** 512MB minimum, 1GB+ recommended
- **Disk:** 5GB for base + jail + OpenClaw, more for workspaces
- **Network:** Ethernet or WiFi interface

### Software

- **FreeBSD:** 15.0 or later (tested on 15.0)
- **ZFS:** Recommended for dataset management
- **Node.js:** Version 20+ (node22 recommended)

---

## Port/Service Requirements

### Host Firewall Rules

```
IN:  None (all inbound blocked by default)
OUT: DNS (53/udp), HTTP (80/tcp), HTTPS (443/tcp)
```

### Jail Network Access

```
IN:  Gateway from host via pf rdr (18789/tcp)
OUT: DNS (53/udp), HTTP (80/tcp), HTTPS (443/tcp)
```

### Localhost Forwarding

```
127.0.0.1:18789 → 10.30.0.10:18789 (via pf)
```

---

## Installation Command Summary

### One-Line Host Setup

```sh
doas pkg install -y jail ezjail sysrc pf git zsh bsddialog nerd-fonts node22 npm-node22
```

### One-Line Jail Setup

```sh
pkg install -y ca_root_nss curl git jq tmux node22 npm-node22 && npm install -g openclaw@latest
```

---

## Verification Commands

### Check Host Packages

```sh
pkg info | grep -E '(jail|pf|zsh|bsddialog|node22)'
```

### Check Jail Packages

```sh
doas jexec openclaw pkg info | grep -E '(node22|curl|ca_root_nss)'
```

### Verify OpenClaw Installation

```sh
doas jexec openclaw openclaw --version
```

### Verify Node.js Version

```sh
# Host
node --version  # Should show v22.x.x

# Jail
doas jexec openclaw node --version
```

---

## Package Sources

All packages available from official FreeBSD repositories:

```sh
# Update package repository
doas pkg update -f

# Upgrade all packages
doas pkg upgrade
```

---

## Troubleshooting Package Issues

### "Package not found"

```sh
# Update package database
doas pkg update -f

# Search for package
doas pkg search <package-name>
```

### Node.js version conflicts

```sh
# Remove old node versions
doas pkg remove node20 npm-node20

# Install node22
doas pkg install -y node22 npm-node22

# Verify
node --version
```

### npm global install fails

```sh
# Fix npm global directory permissions
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
export PATH=~/.npm-global/bin:$PATH

# Or install as root (in jail)
doas jexec openclaw npm install -g openclaw@latest
```

---

## Package Update Strategy

### Host System

```sh
# Weekly: Update package database
doas pkg update

# Monthly: Upgrade all packages
doas pkg upgrade

# Quarterly: Upgrade FreeBSD version
doas freebsd-update fetch install
```

### Jail System

```sh
# Update jail packages
doas jexec openclaw pkg update
doas jexec openclaw pkg upgrade

# Update OpenClaw
doas jexec openclaw npm update -g openclaw
```

---

## Disk Space Requirements

| Component | Space Required |
|-----------|----------------|
| FreeBSD base system | ~1.5 GB |
| Host packages | ~500 MB |
| Jail base | ~500 MB |
| Jail packages | ~200 MB |
| OpenClaw + node_modules | ~200 MB |
| Working space | Variable |
| **Total Minimum** | **~3 GB** |
| **Recommended** | **10 GB+** |

---

## Network Bandwidth Requirements

### Installation

- Initial package download: ~1.5 GB
- npm package download: ~100 MB

### Runtime

- Minimal (API calls only)
- Variable based on workload

---

Last Updated: 2025-02-01
