# Troubleshooting Guide

Common issues and solutions for OpenClaw on FreeBSD.

---

## Connection Issues

### "Connection refused" to localhost:18789

**Symptoms:**
```
$ curl http://127.0.0.1:18789/
curl: (7) Failed to connect to 127.0.0.1 port 18789 after 0 ms: Couldn't connect to server
```

**Possible Causes:**

1. **socat not running**
   ```sh
   doas service openclaw_forward status
   # If not running:
   doas service openclaw_forward start
   ```

2. **Jail gateway not running**
   ```sh
   doas jexec openclaw service openclaw_gateway status
   # If not running:
   doas jexec openclaw service openclaw_gateway start
   ```

3. **Port conflict**
   ```sh
   # Check if something else is using port 18789
   sockstat -4l | grep 18789
   ```

### "No route to host" from host to jail

**Test connectivity:**
```sh
# Ping jail from host
ping -c 3 10.30.0.10

# Should respond
```

**If no response:**

1. **Check bridge exists**
   ```sh
   ifconfig bridge0
   # Should show: inet 10.30.0.1
   ```

2. **Check pf allows bridge traffic**
   ```sh
   doas pfctl -sr | grep bridge0
   # Should show: pass quick on bridge0 all
   ```

3. **Restart networking**
   ```sh
   doas service netif restart
   doas service jail restart openclaw
   ```

---

## Jail Issues

### Jail won't start

**Debug steps:**

1. **Try manual start with verbose output**
   ```sh
   doas jail -c -v -f /etc/jail.conf.d/openclaw.conf openclaw
   ```

2. **Check system logs**
   ```sh
   doas tail -f /var/log/messages
   ```

3. **Verify jail configuration**
   ```sh
   # Check syntax
   doas jail -c -n -f /etc/jail.conf.d/openclaw.conf openclaw
   ```

4. **Check fstab syntax**
   ```sh
   cat /etc/jail.fstab.openclaw
   # Verify tab separators, not spaces
   ```

**Common Issues:**

- **Bridge doesn't exist:** Create with `doas service netif restart`
- **Bad fstab syntax:** Use tabs, not spaces between columns
- **Mount points don't exist:** Create with `mkdir -p`

### Jail starts but network doesn't work

**Inside the jail, verify:**

```sh
# Enter jail
doas jexec openclaw

# Check interface
ifconfig epair0b
# Should show: inet 10.30.0.10

# Check route
netstat -rn
# Should show default route to 10.30.0.1

# Test DNS
nslookup freebsd.org

# Test external connectivity
fetch -qo- https://www.freebsd.org | head
```

**If DNS fails:**
```sh
# Check resolv.conf in jail
cat /etc/resolv.conf

# Should have nameservers, if not:
doas cp /etc/resolv.conf /usr/jails/openclaw/etc/
```

**If external connectivity fails:**
```sh
# Check pf NAT rules
doas pfctl -sn
# Should show: nat on rge0 from 10.30.0.0/24 to any -> (rge0)

# Check pf allows outbound
doas pfctl -sr | grep "10.30.0"
```

---

## Service Issues

### Gateway crashes on startup

**Check logs:**
```sh
doas jexec openclaw tail -n 100 /var/log/openclaw_gateway.log
```

**Common Issues:**

1. **Clipboard module missing**
   ```sh
   doas jexec openclaw test -f \
     /usr/local/lib/node_modules/openclaw/node_modules/@mariozechner/clipboard-freebsd-x64/index.js
   echo $?  # Should be 0
   
   # If missing, re-run installer
   doas ./openclaw-freebsd-install.sh
   ```

2. **Node not in PATH**
   ```sh
   doas jexec openclaw su - your-username -c 'which node'
   # Should show: /usr/local/bin/node
   
   # If not found:
   doas jexec openclaw pkg install -y node22
   ```

3. **Config parse error**
   ```sh
   # Fix config
   doas jexec openclaw su - your-username -c 'openclaw doctor --fix'
   ```

4. **Permission issues**
   ```sh
   # Check ownership
   doas jexec openclaw ls -la /var/run/openclaw/
   doas jexec openclaw ls -la /home/your-username/.openclaw/
   
   # Fix if needed
   doas jexec openclaw chown -R your-username:your-username \
     /var/run/openclaw /home/your-username/.openclaw
   ```

### socat keeps dying

**Check logs:**
```sh
doas tail -n 100 /var/log/openclaw_forward.log
```

**Common Issues:**

1. **Jail gateway not running**
   - socat can't connect if jail gateway isn't up
   - Start jail gateway first, then socat

2. **Port already in use**
   ```sh
   sockstat -4l | grep 18789
   # Kill conflicting process
   ```

3. **Start order matters**
   ```sh
   # Correct order:
   doas service jail start openclaw
   doas jexec openclaw service openclaw_gateway start
   doas service openclaw_forward start
   ```

---

## Performance Issues

### High CPU usage

**Check what's running:**
```sh
# In jail
doas jexec openclaw top

# Look for node processes consuming CPU
```

**Common causes:**
- Long-running OpenClaw tasks
- Busy loops in agent code
- Memory leaks

**Solutions:**
```sh
# Restart gateway
doas jexec openclaw service openclaw_gateway restart

# Check logs for errors
doas jexec openclaw tail -f /var/log/openclaw_gateway.log
```

### Slow network performance

**Test network speed:**
```sh
# From jail to internet
doas jexec openclaw fetch -o /dev/null https://www.freebsd.org

# Should be fast
```

**If slow:**

1. **Check interface speed**
   ```sh
   ifconfig rge0  # Your WAN interface
   # Should show high speed (1000baseT, 2500baseT, etc.)
   ```

2. **Check pf state table**
   ```sh
   doas pfctl -vsi
   # Look for dropped packets
   ```

3. **Test without pf**
   ```sh
   doas pfctl -d  # Disable pf temporarily
   # Test again
   doas pfctl -e  # Re-enable
   ```

---

## Installation Issues

### "pkg: not found" in jail

**Bootstrap pkg:**
```sh
doas jexec openclaw env ASSUME_ALWAYS_YES=YES pkg bootstrap
```

### npm install fails

**Common issues:**

1. **No internet in jail**
   - See [Jail network doesn't work](#jail-starts-but-network-doesnt-work)

2. **Certificate issues**
   ```sh
   doas jexec openclaw pkg install -y ca_root_nss
   ```

3. **Out of disk space**
   ```sh
   df -h
   # Check available space
   ```

### ZFS dataset creation fails

**Check ZFS pool exists:**
```sh
zpool list
# Should show your pool (zroot, etc.)
```

**Check available space:**
```sh
zpool list -o name,size,alloc,free
```

**Create manually if needed:**
```sh
doas zfs create -o mountpoint=/usr/jails zroot/usr/jails
```

---

## Configuration Issues

### Can't access Web UI after reboot

**Services don't start on boot by default. Enable them:**

```sh
# Host
doas sysrc pf_enable="YES"
doas sysrc jail_enable="YES"
doas sysrc openclaw_forward_enable="YES"

# Jail (via rc.conf in jail)
doas jexec openclaw sysrc openclaw_gateway_enable="YES"
```

### Token authentication fails

**Get current token:**
```sh
doas jexec openclaw su - your-username -c 'cat ~/.openclaw/gateway.token'
```

**Regenerate token:**
```sh
doas jexec openclaw su - your-username -c '
  openssl rand -hex 32 > ~/.openclaw/gateway.token
  chmod 600 ~/.openclaw/gateway.token
'

# Update config with new token
doas jexec openclaw su - your-username -c 'vi ~/.openclaw/openclaw.json'
```

### API keys not working

**Check .env file:**
```sh
doas jexec openclaw su - your-username -c 'cat ~/.openclaw/.env'
```

**Format should be:**
```
ANTHROPIC_API_KEY=sk-ant-xxx
OPENAI_API_KEY=sk-xxx
```

**No quotes, no spaces around `=`**

---

## Debugging Commands

### Check all services

```sh
# Jail
doas jls

# Firewall
doas pfctl -sr | head -20

# Host forwarder
doas service openclaw_forward status
sockstat -4l | grep 18789

# Jail gateway
doas jexec openclaw service openclaw_gateway status
doas jexec openclaw sockstat -4l | grep 18789

# Network
ifconfig bridge0
doas jexec openclaw ifconfig epair0b
doas jexec openclaw netstat -rn
```

### View all logs

```sh
# System logs
doas tail -f /var/log/messages

# socat logs
doas tail -f /var/log/openclaw_forward.log

# Gateway logs
doas jexec openclaw tail -f /var/log/openclaw_gateway.log

# pf logs
doas tcpdump -n -e -ttt -i pflog0
```

### Test connectivity

```sh
# Host to jail
ping -c 3 10.30.0.10
fetch -qo- http://10.30.0.10:18789/ | head

# Host to localhost
fetch -qo- http://127.0.0.1:18789/ | head

# Jail to internet
doas jexec openclaw ping -c 3 8.8.8.8
doas jexec openclaw fetch -qo- https://www.freebsd.org | head
```

---

## Recovery Procedures

### Complete service restart

```sh
# Stop everything
doas service openclaw_forward stop
doas jexec openclaw service openclaw_gateway stop
doas service jail stop openclaw

# Start everything
doas service jail start openclaw
doas jexec openclaw service openclaw_gateway start
doas service openclaw_forward start

# Verify
doas service openclaw_forward status
doas jexec openclaw service openclaw_gateway status
fetch -qo- http://127.0.0.1:18789/ | head
```

### Reset OpenClaw configuration

```sh
# Backup old config
doas jexec openclaw su - your-username -c '
  cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak
'

# Regenerate
doas jexec openclaw su - your-username -c 'openclaw doctor --fix'

# Restart
doas jexec openclaw service openclaw_gateway restart
```

### Rebuild jail (preserves data)

```sh
# Stop services
doas service openclaw_forward stop
doas jexec openclaw service openclaw_gateway stop
doas service jail stop openclaw

# Destroy jail root only (ZFS datasets with data persist!)
doas zfs destroy zroot/usr/jails/openclaw

# Recreate
doas zfs create -o mountpoint=/usr/jails/openclaw zroot/usr/jails/openclaw
doas tar -xf /usr/freebsd-dist/base.txz -C /usr/jails/openclaw

# Recreate mount points
doas mkdir -p /usr/jails/openclaw/home/your-username/ocDownloads
doas mkdir -p /usr/jails/openclaw/var/run/openclaw-requests

# Copy resolv.conf
doas cp /etc/resolv.conf /usr/jails/openclaw/etc/

# Re-run installer
doas ./openclaw-freebsd-install.sh
```

---

## Getting Help

If you can't resolve the issue:

1. **Check logs** - Most issues show errors in logs
2. **Search issues** - GitHub issues may have solutions
3. **FreeBSD forums** - [forums.freebsd.org](https://forums.freebsd.org/)
4. **File an issue** - Include logs and system info

**Include in bug reports:**
```sh
# System info
uname -a
freebsd-version

# Service status
doas jls
doas service openclaw_forward status
doas jexec openclaw service openclaw_gateway status

# Logs (last 50 lines)
doas tail -n 50 /var/log/openclaw_forward.log
doas jexec openclaw tail -n 50 /var/log/openclaw_gateway.log
```

---

**Last Updated:** 2025-02-01
