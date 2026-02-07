# OpenClaw on FreeBSD 15

![FreeClaw Logo](logo/freeclaw-logo-text.png)


**Production-ready OpenClaw deployment using VNET jails, socat forwarding, and ZFS storage**

[![FreeBSD](https://img.shields.io/badge/FreeBSD-15.0-red?logo=freebsd)](https://www.freebsd.org/)
[![License](https://img.shields.io/badge/license-BSD--2--Clause-blue.svg)](LICENSE)

---

## Overview

This repository contains a complete, tested setup for running [OpenClaw](https://github.com/openclaw/openclaw) on FreeBSD 15 using:

- **VNET jails** for complete network isolation
- **socat forwarding** for localhost → jail connectivity
- **ZFS datasets** for persistent storage
- **Automated installation** via shell script
- **rc.d services** for proper FreeBSD integration

---

## Quick Start

**Prerequisites:** FreeBSD 15.0+, root/doas access, 5GB+ free space

```
# 1. Clone this repository
git clone https://github.com/yourusername/openclaw-freebsd.git
cd openclaw-freebsd

# 2. Run the automated installer
chmod +x openclaw-freebsd-install.sh
doas ./openclaw-freebsd-install.sh

# 3. Access the Web UI
firefox http://127.0.0.1:18789/
```

**Detailed guide:** See [docs/INSTALL.md](docs/INSTALL.md)

---

## Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| **[INSTALL.md](docs/INSTALL.md)** | Complete installation guide | All users |
| **[HARDWARE.md](docs/HARDWARE.md)** | Tested hardware specifications | Reference |
| **[PACKAGES.md](docs/PACKAGES.md)** | Required packages and dependencies | Reference |
| **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** | Common issues and solutions | When things break |

---

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│ FreeBSD 15 Host                                            │
│                                                            │
│  127.0.0.1:18789 ◄── socat ◄── bridge0 (10.30.0.1)         │
│                                    │                       │
│                                    │ epair0a               │
│  ┌─────────────────────────────────▼──────────────┐        │
│  │ Jail: openclaw (VNET)                          │        │
│  │   - IP: 10.30.0.10/24                          │        │
│  │   - OpenClaw Gateway: 0.0.0.0:18789            │        │
│  │   - User: <your-username>                      │        │
│  │   - Storage: ZFS + nullfs mounts               │        │
│  └────────────────────────────────────────────────┘        │
└────────────────────────────────────────────────────────────┘
```

**Key Features:**
- Complete network isolation via VNET
- Persistent storage independent of jail lifecycle
- Native FreeBSD service integration (rc.d)
- Secure localhost-only access by default

---

## Repository Structure

```
openclaw-freebsd/
├── README.md                           # This file
├── LICENSE                             # BSD-2-Clause
├── openclaw-freebsd-install.sh         # Automated installer
├── openclaw-tui.zsh                    # Optional TUI manager
├── docs/
│   ├── INSTALL.md                      # Complete installation guide
│   ├── QUICKSTART.md                   # Fast setup guide
│   ├── HARDWARE.md                     # Tested hardware specs
│   ├── PACKAGES.md                     # Package requirements
│   └── TROUBLESHOOTING.md              # Problem solving
├── config/
│   ├── pf.conf.example                 # Firewall configuration
│   ├── jail.conf.example               # Jail configuration
│   ├── jail.fstab.example              # nullfs mounts
│   ├── openclaw_forward.rc             # Host socat service
│   └── openclaw_gateway.rc             # Jail gateway service
└── .github/
    └── ISSUE_TEMPLATE.md               # Bug report template
```

---

## What Gets Installed

### On the Host

- **Network:** bridge0 interface (10.30.0.1/24)
- **Firewall:** pf rules for NAT and filtering
- **Service:** `openclaw_forward` (socat forwarding)
- **ZFS:** Datasets for persistent storage

### Inside the Jail

- **Network:** VNET with IP 10.30.0.10/24
- **Software:** Node.js 22, OpenClaw, dependencies
- **Service:** `openclaw_gateway` (OpenClaw gateway)
- **Config:** Token authentication, workspace limits

---

### This setup has been tested on:

- **System:** ASRock B650M PG Riptide Desktop
- **CPU:** AMD Ryzen 5 7600 (6-core, 12-thread)
- **RAM:** 32GB DDR5-4800
- **Storage:** Dual NVMe SSDs
- **Network:** Realtek RTL8125 2.5GbE

See [docs/HARDWARE.md](docs/HARDWARE.md) for complete specifications.

---

## Security

### Default Security Posture

- ✅ **Localhost only:** Web UI accessible only via 127.0.0.1
- ✅ **Token authentication:** Required for all API access
- ✅ **Jail isolation:** Complete network and filesystem separation
- ✅ **Workspace limits:** OpenClaw restricted to specific directory
- ✅ **Firewall:** Only DNS, HTTP, HTTPS allowed outbound from jail

### Accessing Remotely (Optional)

See [docs/INSTALL.md#tailscale-access](docs/INSTALL.md#tailscale-access)

---

## Upgrading

### Upgrade OpenClaw

```sh
doas jexec openclaw service openclaw_gateway stop
doas jexec openclaw npm update -g openclaw
doas jexec openclaw service openclaw_gateway start
```

### Rebuild Jail (preserves data)

```
# Stop services
doas service openclaw_forward stop
doas jexec openclaw service openclaw_gateway stop
doas service jail stop openclaw

# Destroy and recreate jail root
doas zfs destroy zroot/usr/jails/openclaw
doas zfs create -o mountpoint=/usr/jails/openclaw zroot/usr/jails/openclaw
doas tar -xf /usr/freebsd-dist/base.txz -C /usr/jails/openclaw

# Re-run installer
doas ./openclaw-freebsd-install.sh
```

---

## Contributing

Contributions welcome! Please:

1. Test on other releases
2. Update documentation
4. Add to CHANGELOG.md

---

## Compatibility

| Component | Status | Notes |
|-----------|--------|-------|
| FreeBSD 15.0 | ✅ Tested | Primary target |
| FreeBSD 14.x | ⚠️ Should work | Untested |
| AMD GPUs | ✅ Works | amdgpu driver |
| NVIDIA GPUs | ⚠️ Untested | Should work |
| Intel GPUs | ⚠️ Limited | FreeBSD driver limitations |

---

## Credits

- **OpenClaw:** [Anthropic OpenClaw Project](https://github.com/anthropics/openclaw)
- **FreeBSD:** [The FreeBSD Project](https://www.freebsd.org/)
- **bsddialog:** [FreeBSD dialog library](https://gitlab.com/alfix/bsddialog)

---

## License

BSD-2-Clause License - see [LICENSE](LICENSE) file for details.

Configuration files and documentation: CC0 / Public Domain

---

## Support

- **Documentation:** [docs/](docs/)
- **Issues:** [GitHub Issues](https://github.com/KLD997/openclaw-freebsd/issues)
- **FreeBSD Forums:** [forums.freebsd.org](https://forums.freebsd.org/)
- **OpenClaw Docs:** Check upstream project

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

