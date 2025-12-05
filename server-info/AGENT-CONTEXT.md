# Agent Context & Runbook (for future agent sessions)

This file documents the host, the important files, actions previously taken, and steps a future agent needs to continue safely.

## Purpose
This file provides concise, practical operational context and instructions for future automated or interactive agent sessions. It summarizes the changes, useful commands, and pointers for safe operations.

---

## Current server state (short)
- OS: Ubuntu 24.04.3 LTS, kernel: 6.8.0-88-generic
- Hostname: home-server-1
- Docker containers: photoprism, mariadb, portainer, n8n, ollama, open-webui, uptime-kuma, watchtower, etc.
- Timer/service: `photoprism-ledger.timer` active (weekly schedule via drop-in); `photoprism-ledger.service` runs `/usr/local/bin/run-photoprism-ledger.sh` as user `azizelo` (Type=oneshot).
- rclone: Non-snap rclone installed at `/usr/local/bin/rclone` (v1.72.0) - used to avoid snap cgroup mismatch.

---

## Important live files (and what they are)
- `/usr/local/bin/run-photoprism-ledger.sh` — wrapper; sources `/var/lib/server_env`, sends Uptime Kuma heartbeats on success/failure, executes the original script.
- `/usr/local/bin/run-photoprism-ledger.sh.orig` — the original script which performs rclone copy and photoprism_ledger python pipeline.
- `/etc/systemd/system/photoprism-ledger.service` — systemd unit (Type=oneshot) that runs the wrapper as user `azizelo`.
- `/etc/systemd/system/photoprism-ledger.timer` — the timer file; drop-ins exist at `/etc/systemd/system/photoprism-ledger.timer.d/`.
  - Drop-in overrides:
    - `/etc/systemd/system/photoprism-ledger.timer.d/override.conf` — currently sets `OnCalendar=weekly`.
    - `/etc/systemd/system/photoprism-ledger.timer.d/description.conf` — currently `Weekly PhotoPrism Ledger Pipeline`.
- `/var/lib/server_env` — local env file with the Uptime Kuma push URLs and other server-local secrets (permissions 600). Do NOT commit this to git.
- `/var/lib/server_state.yaml` — authoritative baseline YAML snapshot saved by the agent (permissions 600).
- `/var/log/rclone-aziz.log`, `/var/log/rclone-mouna.log` — rclone log files used by the tasks (if configured).

---

## Files & templates in the repo (server-info)
- `server-info/scripts/run-photoprism-ledger.sh.orig.template` — sanitized original script template (safe to commit).
- `server-info/scripts/run-photoprism-ledger.wrapper.template` — sanitized wrapper template; tokens replaced with placeholders.
- `server-info/systemd/photoprism-ledger.timer.d/override.conf.template` — template for OnCalendar=weekly drop-in.
- `server-info/systemd/photoprism-ledger.timer.d/description.conf.template` — description template.
- `server-info/tools/generate_server_state_fixed.sh` — tool for generating baseline YAML snapshots.
- `server-info/tools/apply-templates.sh` — helper to display diffs or apply sanitized templates to live paths (requires `--apply` to write changes and will create backups); default is dry-run.
- `server-info/tools/server-env-edit.sh.example` — example/editor helper to edit `/var/lib/server_env` as root (keeps a changelog).
- `server-info/examples/server_env.example` — template for local secrets.
- `server-info/audit/` — saved audit snapshots and the generated baseline YAML draft.
- `server-info/AGENT-CONTEXT.md` — this file (context & runbook).

---

## How to apply templates safely (recommended workflow)
1. Review diffs in the repo first using the `apply-templates.sh` script in show mode:
   ```bash
   cd ~/server-ops
   sudo server-info/tools/apply-templates.sh --show
   ```
   This displays diffs between live files and template files.

2. When ready to apply (after review), apply templates with the `--apply` switch. This will backup current live files with a `.bak.<timestamp>` suffix and copy the template to the destination. It will also reload systemd and restart the timer:
   ```bash
   sudo server-info/tools/apply-templates.sh --apply
   ```

3. After apply, verify the changes are as expected and that the timer is active and scheduled correctly:
   ```bash
   systemctl daemon-reload
   systemctl restart photoprism-ledger.timer
   systemctl status photoprism-ledger.timer --no-pager
   systemctl status photoprism-ledger.service --no-pager
   ```

**Notes**:
- `apply-templates.sh` is a convenience helper; it requires `sudo` to copy into `/usr/local/bin` and `/etc/systemd/`.
- All templates are sanitized; before running `--apply`, ensure `/var/lib/server_env` is set with your actual secrets.

---

## How to manage secrets
- Store push URLs (Uptime Kuma), or other small secrets in `/var/lib/server_env` using the secure helper:
  ```bash
  sudo /usr/local/bin/server-env-edit.sh
  ```
  This keeps the permissions and ownership in a standardized way and appends a redacted changelog line to `/var/lib/server_env.changelog`.

- Do NOT commit `/var/lib/server_env` to the repo; `server-info/examples/server_env.example` is the templated placeholder to be committed.

---

## How to test Uptime Kuma heartbeats (safe test commands)
- Success test (simulates success heartbeat using the push URL):
  ```bash
  curl -fsS --max-time 10 "https://status/api/push/<SUCCESS_TOKEN>?status=up&msg=OK&ping=$(date +%s)" || true
  ```
- Failure test (simulate a failed run):
  ```bash
  curl -fsS --max-time 10 "https://status/api/push/<FAILURE_TOKEN>?status=down&msg=FAILED&ping=$(date +%s)" || true
  ```
- The wrapper will append an epoch timestamp to the `ping=` endpoint automatically, making it valid for Kuma.
- If you're testing the wrapper script: back up live script or use the wrapper's trap to ensure it sends the correct push on error.

---

## How to verify schedule, last run, and imported counts
- Check timer next trigger and status:
  ```bash
  systemctl status photoprism-ledger.timer --no-pager
  systemctl list-timers --all | grep photoprism-ledger
  ```
- Check the service run (last successful run suggested by systemd):
  ```bash
  systemctl status photoprism-ledger.service --no-pager
  journalctl -u photoprism-ledger.service --no-pager -n 200
  ```
- Check logs for photoprism (for indexing status and import counts):
  ```bash
  docker logs photoprism --since '1h' --tail 200
  ```
- The wrapper writes rclone logs into `/var/log/rclone-aziz.log` and `/var/log/rclone-mouna.log` if enabled — check these for rclone-related errors.

---

## How to regenerate or update the baseline
- Regenerate a fresh server baseline draft YAML with the included script and review it:
  ```bash
  cd ~/server-ops
  bash server-info/tools/generate_server_state_fixed.sh
  # Saved draft will be in /tmp/server_state-draft-fixed.yaml
  sed -n '1,240p' /tmp/server_state-draft-fixed.yaml
  # After reviewing, copy it into /var/lib and the repo (if you want):
  sudo cp /tmp/server_state-draft-fixed.yaml /var/lib/server_state.yaml
  cp /tmp/server_state-draft-fixed.yaml server-info/audit/server_state-$(date -u +%Y%m%dT%H%M%SZ)-draft.yaml
  git add server-info/audit/server_state-*.yaml
  git commit -m "Add server state baseline snapshot"
  git push
  ```

**Note:** /var/lib/server_state.yaml is owned by root and has 600 perms. The repo only contains sanitized copies.

---

## Rollback steps & recovery
- If `apply-templates.sh --apply` is used, backups are created at the destination (e.g., `/usr/local/bin/run-photoprism-ledger.sh.bak.<timestamp>`). To restore a backup:
  ```bash
  sudo cp -a /usr/local/bin/run-photoprism-ledger.sh.bak.2025... /usr/local/bin/run-photoprism-ledger.sh
  sudo chmod 755 /usr/local/bin/run-photoprism-ledger.sh
  sudo systemctl daemon-reload
  sudo systemctl restart photoprism-ledger.timer
  ```

- If systemd drop-ins are overwritten, `apply-templates.sh` created a `.bak.<timestamp>` backup of the original files — restore by copying back and reloading systemd.

---

## Known caveats & notes
- Snap-packaged `rclone` caused service failures when run from systemd due to cgroup/snap runtime mismatch; we switched to upstream rclone installed in `/usr/local/bin/rclone`.
- OneDrive has API rate limiting; large full listings may generate long pacer/backoff messages — consider incremental sync or segmented listing to reduce rate-limit pressure.
- The wrapper sends push notifications via Uptime Kuma only if the process finishes or any commands fail (trap ERR). It may not run for immediate SIGKILL or kernel-level process termination; add a systemd `OnFailure` notifier if you want guaranteed pings for those scenarios (we did not add OnFailure per your instruction).

---

## Quick check commands summary
- Show wrapper & original script heads (sanitized):
  ```bash
  sudo sed -n '1,200p' /usr/local/bin/run-photoprism-ledger.sh
  sudo sed -n '1,200p' /usr/local/bin/run-photoprism-ledger.sh.orig
  ```
- Show timer & service status
  ```bash
  systemctl status photoprism-ledger.timer --no-pager
  systemctl status photoprism-ledger.service --no-pager
  systemctl list-timers --all | grep photoprism-ledger
  ```
- If you need to update the push URLs
  ```bash
  sudo /usr/local/bin/server-env-edit.sh   # Add/modify SUCCESS_HEARTBEAT_URL & FAILURE_HEARTBEAT_URL
  ```
- Test push ping
  ```bash
  curl -fsS --max-time 10 "<SUCCESS_URL>$(date +%s)" || true
  ```

---

## Who to contact (local)
- The repository is pushed to: https://github.com/azizelo/home-server.git
- Repo local path: `~/server-ops`
- Local artifacts & live location: `/usr/local/bin/`, `/etc/systemd/system/`, `/var/lib/` (env & baseline)

---

## Final note for future agents
- Always check `/var/lib/server_env` first for secrets and do not print or log it. Use the example file in the repo as a template and keep secrets out of git. Follow the `apply-templates.sh --show` -> review -> `--apply` path for changes.

