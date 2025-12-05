#!/usr/bin/env bash
# Safe audit script - non-destructive
# Usage: run as normal user; re-run with sudo for more privileged output
set -u

OUTBASE="/home/azizelo/server-ops/server-info"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUTDIR="${OUTBASE}/audit-${TS}"
mkdir -p "${OUTDIR}"

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "${OUTDIR}/audit.log"; }

# Run a command, save stdout/stderr to a file and record exit code
run() {
  local name="$1"; shift
  local file="${OUTDIR}/${name}.txt"
  log "START ${name}"
  {
    printf '=== Command: %s\n\n' "$*"
    "$@" 2>&1
    printf '\n=== Exit: %d\n' "${PIPESTATUS[0]:-0}"
  } > "${file}" || true
  log "END ${name} -> ${file}"
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Basic metadata
run "meta-date" date
run "meta-whoami" whoami
run "meta-hostname" hostnamectl || run "meta-hostname-fallback" cat /etc/hostname
run "meta-uname" uname -a
if has_cmd lsb_release; then
  run "meta-lsb_release" lsb_release -a
fi
if [ -r /etc/os-release ]; then
  run "meta-os-release" cat /etc/os-release
fi

# Uptime, load, processes
run "meta-uptime" uptime
run "meta-top" top -b -n1 | head -n 200
run "meta-ps" ps aux --forest | head -n 500

# Disk & filesystem
run "disk-df" df -h
run "disk-lsblk" lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT
run "disk-du-var" du -sh /var 2>/dev/null || echo "/var du not readable without sudo"

# Network and ports
if has_cmd ss; then
  run "net-ss" ss -tulpen
else
  run "net-netstat" netstat -tulpen || true
fi
run "net-ip-addr" ip addr
run "net-ip-route" ip route

# Firewall (may require sudo)
if has_cmd ufw; then
  run "fw-ufw-status" ufw status verbose || true
fi
if has_cmd iptables-save; then
  run "fw-iptables-save" iptables-save || echo "iptables-save not permitted without sudo"
fi

# systemd & services
if has_cmd systemctl; then
  run "systemd-list-units" systemctl list-units --type=service --all --no-pager
  run "systemd-list-unit-files" systemctl list-unit-files --type=service --no-pager
  run "systemd-failed" systemctl --no-pager --failed || true
fi
run "systemd-timers" systemctl list-timers --all --no-pager || true

# journal (non-root may be limited)
if has_cmd journalctl; then
  run "journal-last-500" journalctl -b -n 500 --no-pager || echo "journalctl output may be limited (requires sudo)"
fi

# Users & auth (no /etc/shadow)
run "users-id" id
run "users-groups" groups || true
run "users-passwd" getent passwd
run "users-group-list" getent group

# Crontab: current user only
run "crontab-user" crontab -l 2>&1 || echo "No crontab for current user or not allowed"

# Packages (distro-specific)
if has_cmd dpkg; then
  run "packages-dpkg" dpkg -l | head -n 500
elif has_cmd rpm; then
  run "packages-rpm" rpm -qa | head -n 500
fi

# Common config files (if readable)
for f in /etc/hosts /etc/hostname /etc/resolv.conf; do
  if [ -r "$f" ]; then
    cp -f "$f" "${OUTDIR}/config-$(basename "$f")"
  fi
done

# Docker info (non-destructive)
if has_cmd docker; then
  run "docker-version" docker version
  run "docker-info" docker info
  run "docker-images" docker images --all --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
  run "docker-containers" docker ps -a --format '{{.Image}} {{.Names}} {{.Status}}'
else
  echo "docker: not found" > "${OUTDIR}/docker-not-found.txt"
fi

# Docker daemon config if readable
if [ -r /etc/docker/daemon.json ]; then
  cp -f /etc/docker/daemon.json "${OUTDIR}/config-daemon.json"
fi

# Non-recursive listings for large dirs
if [ -d /etc/systemd/system ]; then
  run "ls-etc-systemd" ls -la /etc/systemd/system
fi
if [ -d /var/lib/docker ]; then
  run "ls-var-lib-docker" ls -la /var/lib/docker | head -n 200
fi

# Summary
{
  echo "Audit timestamp: ${TS}"
  echo "Output directory: ${OUTDIR}"
  echo ""
  echo "Files created:"
  ls -la "${OUTDIR}"
} > "${OUTDIR}/README.txt"

log "AUDIT COMPLETE: ${OUTDIR}"
echo "Audit complete. Outputs saved to ${OUTDIR}"