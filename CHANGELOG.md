# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-02-01

### Added
- Initial release of OpenClaw FreeBSD setup
- Automated installation script with username prompting
- VNET jail configuration with full network isolation
- socat forwarding service for localhost → jail connectivity
- ZFS dataset structure for persistent storage
- pf firewall configuration with NAT and filtering
- nullfs mounts for shared directories
- rc.d service integration (openclaw_gateway, openclaw_forward)
- Complete documentation set (INSTALL, QUICKSTART, TROUBLESHOOTING, HARDWARE, PACKAGES)
- Optional bsddialog-based TUI manager
- Clipboard module stub for FreeBSD compatibility
- Configuration examples for all components
- BSD-2-Clause licensed

### Tested
- FreeBSD 15.0-RELEASE on AMD Ryzen 5 7600
- AMD Radeon RX 7600 GPU with amdgpu driver
- Realtek RTL8125 2.5GbE network interface
- ZFS root filesystem
- 32GB DDR5 RAM

### Known Issues
- None at release

## [Unreleased]

### Planned
- FreeBSD 14.x compatibility testing
- Alternative forwarding methods (without socat)
- Multiple jail instance support
- Automated backup scripts
- Ansible playbook
- Performance tuning guide

---

[1.0.0]: https://github.com/yourusername/openclaw-freebsd/releases/tag/v1.0.0
