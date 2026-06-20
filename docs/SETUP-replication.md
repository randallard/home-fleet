# Phase 3 — wire acer → tenx replication

The "do it" checklist for the controller path ([ADR-0002](adr/0002-fleet-topology-acer-primary-tenx-backup-controller.md)
/ [ADR-0003](adr/0003-replication-mechanism-hook-sweep-ff-only-snapshots.md)): acer mirrors
every home to tenx (hook + 15-min sweep, ff-only), tenx accepts **only** receive-only,
ff-only, never-delete, and keeps daily snapshots.

> Prerequisite: Phase 1 (acer up, [SETUP-acer.md](SETUP-acer.md)) and Phase 2 (homes seeded,
> `seed-acer.sh`). Scripts referenced live in [`scripts/replication/`](../scripts/replication/).

## A. tenx side — become a hardened receiver

1. **Install the replication scripts** (on tenx):
   ```bash
   sudo install -d -o "$USER" -g "$USER" /data/git/.replication
   install -m755 scripts/replication/tenx-receive-only-command.sh /data/git/.replication/
   install -m755 scripts/replication/tenx-pre-receive             /data/git/.replication/
   install -m755 scripts/replication/tenx-harden-homes.sh         /data/git/.replication/
   install -m755 scripts/replication/tenx-snapshot.sh             /data/git/.replication/
   ```
2. **Harden every home** (ff-only, no deletes, pre-receive hook):
   ```bash
   /data/git/.replication/tenx-harden-homes.sh            # dry-run
   /data/git/.replication/tenx-harden-homes.sh --apply
   ```
3. **Authorize acer's replication key, receive-only.** On acer, generate a dedicated key
   (`ssh-keygen -t ed25519 -f ~/.ssh/acer-replication -C acer-replication`, no passphrase so the
   hook/timer are non-interactive). Then on tenx add **one line** to `~/.ssh/authorized_keys`:
   ```
   command="/data/git/.replication/tenx-receive-only-command.sh",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAA...acer-replication
   ```
4. **Daily snapshots** — `~/.config/systemd/user/tenx-snapshot.{service,timer}` (or system units):
   ```ini
   # tenx-snapshot.service
   [Service]
   Type=oneshot
   ExecStart=/data/git/.replication/tenx-snapshot.sh
   ```
   ```ini
   # tenx-snapshot.timer
   [Timer]
   OnCalendar=*-*-* 02:30:00
   Persistent=true
   [Install]
   WantedBy=timers.target
   ```
   ```bash
   systemctl --user enable --now tenx-snapshot.timer
   ```

## B. acer side — become the controller

1. **SSH alias to tenx** (FIPS, host-key-pinned, using the dedicated key) —
   `~/.ssh/config.d/tenx-backup.conf`:
   ```sshconfig
   Host tenx-backup
       HostName tenx-rltec.local          # or the Tailscale name tenx-rltec
       User randallard
       IdentityFile ~/.ssh/acer-replication
       IdentitiesOnly yes
       HostKeyAlias tenx-rltec
       StrictHostKeyChecking yes
       KexAlgorithms ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521
       Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes128-ctr
       MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
       HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,rsa-sha2-512,rsa-sha2-256
   ```
   Pin tenx's ECDSA host key under `tenx-rltec` (same `ssh-keyscan … | awk …` flow as
   SETUP-acer.md, step 5). tenx's pin (verify): `SHA256:PTPAcg55PAfGxXV6/hUqiDdfXGl3SKxJNLWGtqby8p8`.
2. **Install the replication scripts** (on acer):
   ```bash
   install -d /data/git/.replication
   install -m755 scripts/replication/acer-mirror-one.sh /data/git/.replication/
   install -m755 scripts/replication/acer-sweep.sh      /data/git/.replication/
   ```
3. **Drop the hook into every home** (and into `seed-acer.sh`'s output for future homes):
   ```bash
   for h in /data/git/*.git; do
     install -m755 scripts/replication/acer-post-receive "$h/hooks/post-receive"
   done
   ```
4. **15-minute sweep** — `~/.config/systemd/user/acer-replicate.{service,timer}`:
   ```ini
   # acer-replicate.service
   [Service]
   Type=oneshot
   ExecStart=/data/git/.replication/acer-sweep.sh
   ```
   ```ini
   # acer-replicate.timer
   [Timer]
   OnCalendar=*:0/15
   Persistent=true
   [Install]
   WantedBy=timers.target
   ```
   ```bash
   systemctl --user enable --now acer-replicate.timer
   ```

## C. Verify
- [ ] **Round-trip:** push a commit to a home on acer → within the hook window it appears on
      tenx (`git ls-remote tenx-backup:/data/git/<repo>.git`). Check
      `/data/git/.replication/audit.log` on acer shows `OK`.
- [ ] **Sweep catch-up:** stop tenx briefly, push to acer (hook logs FAIL), bring tenx back →
      the next sweep logs `OK`.
- [ ] **Force-closed:** from acer, attempt a non-ff push (`git push tenx-backup +<ref>` / a
      rewound branch) → **rejected** by tenx (pre-receive / denyNonFastForwards), audit shows
      `FAIL`. A shell attempt (`ssh tenx-backup whoami`) → **denied**, logged in
      `tenx-access.log`.
- [ ] **Snapshot:** after the timer fires, `/data/git/.snapshots/<repo>/<repo>-<date>.bundle`
      exists and `git bundle verify` passes.

## Notes
- Replication liveness (audit freshness + last-snapshot age) is the signal for the deferred
  monitoring floor — surface it in `gr status` later (PROGRESS §5).
- Keys and host identities are machine-local; everything in `scripts/replication/` is generic
  and committed.
