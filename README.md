# OpenClaw FreeBSD Documentation Package

Complete documentation and tools for running OpenClaw on FreeBSD 15 in a VNET jail with pf forwarding.

---

## Files Included

### Documentation

1. **openclaw-freebsd-complete-guide.md** (Primary Reference)
   - Complete installation and configuration guide
   - Architecture explanation
   - Troubleshooting section
   - Security considerations
   - Advanced configuration (Tailscale, multiple jails)
   - ~300 lines

2. **openclaw-freebsd-quickstart.md** (Quick Start)
   - 30-minute installation walkthrough
   - Copy-paste commands
   - Minimal explanation
   - Quick troubleshooting
   - ~200 lines

3. **openclaw-freebsd-packages.md** (Package Reference)
   - Complete package lists (host and jail)
   - System requirements
   - Disk space requirements
   - Verification commands
   - ~150 lines

### Scripts

4. **openclaw-freebsd-install.sh** (Automated Installer)
   - Installs OpenClaw in existing jail
   - Creates user with matching UID/GID
   - Configures service and systemd-style wrapper
   - Generates authentication token
   - ~400 lines
   - Usage: `doas ./openclaw-freebsd-install.sh`

5. **openclaw-tui.zsh** (TUI Manager)
   - bsddialog-based text UI
   - Manage jail lifecycle
   - Start/stop gateway service
   - View logs and status
   - Run OpenClaw wizards
   - ~350 lines
   - Requires: zsh, bsddialog
   - Usage: `./openclaw-tui.zsh`

---

## Quick Start

1. Read `openclaw-freebsd-quickstart.md`
2. Install host packages
3. Configure ZFS, network, jail, firewall
4. Run `openclaw-freebsd-install.sh`
5. Access UI at http://127.0.0.1:18789/

---

## Documentation Hierarchy

```
Start Here
    ↓
openclaw-freebsd-quickstart.md (30 min install)
    ↓
openclaw-freebsd-complete-guide.md (deep dive)
    ↓
openclaw-freebsd-packages.md (reference)
```

---

## Key Features

### Architecture
- **VNET jail** with full network isolation (10.30.0.10/24)
- **pf rdr forwarding** for localhost access (no socat)
- **ZFS datasets** for persistent storage
- **FreeBSD 15** tested and working

### Security
- Token-based authentication
- Localhost-only access by default
- Workspace isolation
- Jail sandboxing

### Automation
- Automated installer script
- TUI manager for easy control
- rc.d service integration
- Proper PID/log management

---

## System Requirements

- **OS:** FreeBSD 15.0+
- **Filesystem:** ZFS (recommended)
- **RAM:** 512MB minimum, 1GB+ recommended
- **Disk:** 5GB minimum, 10GB+ recommended
- **Network:** Any Ethernet/WiFi interface

---

## Support Matrix

| Feature | Status |
|---------|--------|
| FreeBSD 15 | ✅ Tested |
| FreeBSD 14 | ⚠️  Should work (untested) |
| VNET jails | ✅ Full support |
| pf firewall | ✅ NAT + rdr |
| ZFS datasets | ✅ Recommended |
| UFS filesystem | ⚠️  Works (no snapshots) |
| Tailscale | ✅ Optional |
| Multiple jails | ✅ Supported |

---

## Common Use Cases

### Development Workstation
- Run OpenClaw locally
- Access via browser at localhost
- Isolated from host system

### Remote Server
- SSH tunnel for access
- Optional Tailscale integration
- Secure token authentication

### Multiple Instances
- Separate jails per project
- Different ports per instance
- Isolated workspaces

---

## Troubleshooting Quick Links

**UI not accessible?**
→ See "Troubleshooting" in complete guide

**Jail won't start?**
→ Check jail configuration section

**Gateway crashes?**
→ Run `openclaw doctor --fix`

**Network issues?**
→ Verify pf rules and bridge config

---

## File Manifest

```
.
├── README.md                              (this file)
├── openclaw-freebsd-complete-guide.md     (primary docs)
├── openclaw-freebsd-quickstart.md         (quick start)
├── openclaw-freebsd-packages.md           (package reference)
├── openclaw-freebsd-install.sh            (installer script)
└── openclaw-tui.zsh                       (TUI manager)
```

---

## Installation Order

1. **Review documentation:**
   - Read quickstart guide
   - Understand architecture from complete guide
   - Check package requirements

2. **Prepare system:**
   - Install host packages
   - Create ZFS datasets
   - Configure network (bridge0)
   - Configure firewall (pf)
   - Create jail configuration

3. **Deploy jail:**
   - Extract base system
   - Configure jail networking
   - Start jail

4. **Install OpenClaw:**
   - Run `openclaw-freebsd-install.sh`
   - Verify installation
   - Access Web UI

5. **Install TUI (optional):**
   - Copy `openclaw-tui.zsh` to bin directory
   - Run TUI for easy management

---

## Design Philosophy

Following FreeBSD principles:

- **Simplicity:** Minimal dependencies, clear configuration
- **Reliability:** pf over socat, ZFS snapshots available
- **Security:** Jail isolation, token auth, minimal exposure
- **Transparency:** Human-readable configs, verbose logging
- **Composability:** Standard tools (jail, pf, zfs, rc.d)

---

## Version History

- **v3** (2025-02-01): pf rdr forwarding, updated docs
- **v2** (earlier): socat forwarding approach
- **v1** (initial): Basic jail setup

---

## Credits

- OpenClaw project (upstream)
- FreeBSD project
- bsddialog developers

---

## License

Documentation: Public domain / CC0  
Scripts: BSD-2-Clause (FreeBSD style)  
OpenClaw: Check upstream project

---

## Contributing

Improvements welcome:
- Documentation clarity
- Error handling in scripts
- Additional use cases
- FreeBSD 14 testing

---

## Known Limitations

1. **No native clipboard:** FreeBSD clipboard module is stubbed
2. **pf required:** No alternative forwarding method documented
3. **ZFS recommended:** UFS works but lacks snapshots
4. **Node 22 required:** Older versions untested

---

## Future Enhancements

- [ ] Ansible playbook for automation
- [ ] Multi-instance TUI support
- [ ] Automatic backup scripts
- [ ] Performance tuning guide
- [ ] Desktop integration (xdg-open)

---

**Package Version:** 3.0  
**Last Updated:** 2025-02-01  
**Maintainer:** Community  
**Tested On:** FreeBSD 15.0-CURRENT
