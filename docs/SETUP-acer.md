# Phase 1 — stand up acer-arch as a home server

The "do it" checklist for turning **acer-arch** (recycled box, 1 TB HDD, headless Arch) into the
fleet's **primary** bare-repo host, with the **same FIPS-enforced SSH transport as tenx**
(git-redundancy
[ADR-0005](https://github.com/randallard/git-redundancy/blob/main/docs/adr/0005-fips-crypto-path-a-enforce-approved-algorithms.md)
Path A /
[ADR-0009](https://github.com/randallard/git-redundancy/blob/main/docs/adr/0009-ssh-transport-aliases-mdns-hostkey-pinned.md)).
Result: acer reachable as a bare-repo home over **`acer-lan`** (mDNS) and **`acer-ts`**
(Tailscale), host-key pinned, FIPS algorithms enforced fail-closed.

> Scope: this phase makes acer a *reachable, hardened home server*. It does **not** repoint any
> client's git remotes (that's Phase 4) or wire acer→tenx replication (Phase 3).

## What we're matching (verified on tenx, 2026-06-19)

- **Enforcement is client-side.** tenx keeps all three host keys and sets **no** algorithm
  restrictions in `sshd_config`; the *client alias* pins FIPS kex/cipher/MAC and forces the
  **ECDSA** host key. So acer only needs to **offer an ECDSA host key** — no special `sshd`
  config.
- **FIPS algorithm set** (from the client alias): Kex `ecdh-sha2-nistp{256,384,521}`; Ciphers
  `aes{256,128}-gcm` + `aes{256,128}-ctr`; MACs `hmac-sha2-{512,256}-etm`; host key
  `ecdsa-sha2-nistp*`.
- **mDNS** via Avahi is active on tenx (for `*.local`); **Tailscale** carries the off-LAN path.
  acer is already on the tailnet as `acer-arch` (`100.65.74.108`).
- Client auth key is **ed25519** (FIPS 186-5); `PubkeyAcceptedAlgorithms` left at default.

---

## 1. Base OS & storage *(on acer)*
- [ ] Headless Arch installed (server profile, no desktop).
- [ ] Mount the 1 TB HDD at **`/data`** (add to `/etc/fstab`), then:
      ```bash
      sudo mkdir -p /data/git
      sudo chown "$USER":"$USER" /data/git
      ```
- [ ] Packages + git ≥ 2.38:
      ```bash
      sudo pacman -S --needed git openssh avahi nss-mdns
      git --version    # expect >= 2.38
      ```

## 2. Reachability *(on acer)*
- [ ] Hostname: `sudo hostnamectl set-hostname acer-arch`.
- [ ] mDNS (so `acer-arch.local` resolves on the LAN, matching tenx):
      ```bash
      sudo systemctl enable --now avahi-daemon
      # ensure the hosts: line in /etc/nsswitch.conf includes mdns_minimal, e.g.:
      #   hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns
      ```
- [ ] Tailscale already up — confirm: `tailscale status | grep acer-arch` (→ `100.65.74.108`).
- [ ] From a LAN client: `ping acer-arch.local` (mDNS) and `ping acer-arch` (tailnet) both answer.

## 3. sshd + ECDSA host key *(on acer)*
- [ ] Enable sshd: `sudo systemctl enable --now sshd`.
- [ ] Ensure an ECDSA host key exists (generates any missing types; leaves existing ones):
      ```bash
      sudo ssh-keygen -A
      ls /etc/ssh/ssh_host_ecdsa_key.pub      # must exist
      ```
      No explicit algorithm lines in `sshd_config` — matches tenx; the clients enforce FIPS.
- [ ] **Record acer's ECDSA pin** (you verify against this when pinning on clients):
      ```bash
      ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub      # note the SHA256:… fingerprint
      ```
- [ ] Authorize your client key: append your **ed25519** public key to
      `~/.ssh/authorized_keys` on acer.

## 4. Client transport aliases *(on each client → `~/.ssh/config.d/acer.conf`)*
- [ ] Ensure `~/.ssh/config` has `Include config.d/*.conf` near the top.
- [ ] Create `~/.ssh/config.d/acer.conf` (mirrors tenx's alias, FIPS algorithms, host-key pinned):

      ```sshconfig
      # acer-arch transport (fleet primary). FIPS-approved kex/cipher/MAC, fail-closed;
      # one pinned ECDSA host key serves both LAN (acer-lan) and Tailscale (acer-ts).
      Host acer-lan
          HostName acer-arch.local
          User randallard
          HostKeyAlias acer-arch
          StrictHostKeyChecking yes
          KexAlgorithms ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521
          Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes128-ctr
          MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
          HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,rsa-sha2-512,rsa-sha2-256

      Host acer-ts
          HostName acer-arch
          User randallard
          HostKeyAlias acer-arch
          StrictHostKeyChecking yes
          KexAlgorithms ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521
          Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes128-ctr
          MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
          HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,rsa-sha2-512,rsa-sha2-256
      ```

## 5. Pin acer's ECDSA host key under the alias name *(on each client)*
- [ ] Capture the key under the `HostKeyAlias` name (the `awk` guard drops the keyscan banner):
      ```bash
      ssh-keyscan -t ecdsa acer-arch.local 2>/dev/null \
        | awk 'NF>=3 && $1=="acer-arch.local"{$1="acer-arch"; print}' >> ~/.ssh/known_hosts
      ```
- [ ] **Verify the fingerprint matches what you recorded on acer in step 3** before trusting it:
      ```bash
      ssh-keygen -lf <(ssh-keyscan -t ecdsa acer-arch.local 2>/dev/null)
      ```

## 6. Verify
- [ ] Strict, FIPS-only connect works:
      ```bash
      ssh -o ControlPath=none acer-lan 'echo OK $(hostname)'    # -> OK acer-arch
      ssh -o ControlPath=none acer-ts  'echo OK $(hostname)'    # -> OK acer-arch
      ```
- [ ] FIPS is fail-closed (a non-approved cipher is refused, never downgraded):
      ```bash
      ssh -o ControlPath=none -o Ciphers=3des-cbc acer-lan true 2>&1 | tail -1
      ```

---

## Notes / what's deferred
- **Remote wiring** (clients' git remotes → acer as the primary home) is **Phase 4**, by which
  point acer's `/data/git/*.git` homes exist (seeded in Phase 2).
- **acer→tenx replication** (acer as controller) is **Phase 3**: acer gets its own client alias
  to tenx and a **receive-only** key on tenx.
- This mirrors tenx exactly; if acer's transport ends up diverging, write a transport ADR
  (PROGRESS §5).
