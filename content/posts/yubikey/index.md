---
date: "2026-04-04T21:28:46-04:00"
lastmod: "2026-04-04T21:28:46-04:00"
draft: true
showReadingTime: true
title: "YubiKey 5C NFC: Provisioning, PAM, and LUKS"
summary: "A reference card for setting up a YubiKey from scratch on Arch Linux -- OpenPGP keys, FIDO2 SSH, PAM authentication, and full disk encryption."
description: "Concise reference for provisioning a YubiKey 5C NFC with ed25519 OpenPGP keys, FIDO2 resident SSH keys, PAM login/sudo, and LUKS2 disk encryption on Arch Linux."
tags: ["relevant"]
---

Everything here was done on a YubiKey 5C NFC, firmware 5.4.3, on Arch Linux. Most of it generalises to any YubiKey 5 series and any systemd-based distro. The assumed starting point is a factory-reset key or one you're about to reset.

## Part 1: Provisioning

### Prerequisites

```bash
pacman -S yubikey-manager gnupg pcsclite ccid libfido2
systemctl enable --now pcscd.socket
```

### Fix the CCID conflict

GnuPG's `scdaemon` grabs the USB CCID interface exclusively, which blocks `ykman` from reaching the OpenPGP, OATH, and PIV applets. Fix this by creating `~/.gnupg/scdaemon.conf`:

```
disable-ccid
pcsc-shared
disable-application piv
```

- `disable-ccid` forces scdaemon through pcscd instead of talking USB directly
- `pcsc-shared` opens the reader in shared mode so other PC/SC clients (ykman) can coexist
- `disable-application piv` stops scdaemon probing the PIV applet, which causes conflicts on GPG 2.3+ ([scdaemon docs](https://www.gnupg.org/documentation/manuals/gnupg/Scdaemon-Options.html))

After creating the file:

```bash
gpgconf --kill scdaemon && gpgconf --kill gpg-agent
sudo systemctl restart pcscd
```

Verify both paths work: `gpg --card-status` and `ykman openpgp info`.

### Reset the OpenPGP applet

If the admin PIN is locked or you want a clean slate:

```bash
ykman openpgp reset
```

Default PINs after reset: user `123456`, admin `12345678`.

### Generate ed25519 keys on-device

```bash
gpg --edit-card
```

```
gpg/card> admin
gpg/card> key-attr
```

For each of the three slots (sign, encrypt, auth), select **ECC** then **Curve 25519**. This gives ed25519 for signing/auth and cv25519 for encryption. Admin PIN required.

```
gpg/card> name       # Surname, Given name
gpg/card> lang       # en
gpg/card> generate
```

- Make off-card backup: **no** (keys should never leave the device)
- Expiry: **0** (no expiry -- pointless on a hardware token where the private key can't be extracted; use a revocation cert instead)
- Fill in name, email, confirm

Note the key fingerprint from the output. You'll need it for git.

### Change PINs

```bash
gpg --change-pin
```

Option 1 for user PIN, option 3 for admin PIN. Do this immediately.

### Touch policies

```bash
ykman openpgp keys set-touch sig cached   # admin PIN required
ykman openpgp keys set-touch enc cached
ykman openpgp keys set-touch aut cached
```

`cached` requires a physical tap but caches it for 15 seconds -- good enough for git signing and SSH bursts without requiring a tap per packet. Other options: `on` (every time), `fixed` (every time, can't change without full reset), `off`. [ykman OpenPGP docs](https://docs.yubico.com/software/yubikey/tools/ykman/OpenPGP_Commands.html)

### GPG config files

**`~/.gnupg/gpg-agent.conf`**:

```
default-cache-ttl 600
max-cache-ttl 7200
```

Don't set `pinentry-program` -- the default `/usr/bin/pinentry` auto-selects the right frontend (Qt on KDE, curses over SSH). But you **must** export `GPG_TTY` in your shell profile for the tty fallback to work:

```bash
export GPG_TTY=$(tty)
```

If you need gpg-agent to serve SSH keys via the OpenPGP auth subkey (instead of FIDO2), add `enable-ssh-support` and point `SSH_AUTH_SOCK` to `/run/user/1000/gnupg/S.gpg-agent.ssh`. We don't -- see FIDO2 SSH below.

**`~/.gnupg/gpg.conf`**:

```
default-key your@email.here
personal-digest-preferences SHA512 SHA384 SHA256
personal-cipher-preferences AES256 AES192 AES
personal-compress-preferences ZLIB BZIP2 ZIP Uncompressed
cert-digest-algo SHA512
s2k-digest-algo SHA512
s2k-cipher-algo AES256
charset utf-8
no-comments
no-emit-version
keyid-format 0xlong
list-options show-uid-validity
verify-options show-uid-validity
with-fingerprint
require-cross-certification
no-symkey-cache
```

### Revocation certificate

GPG auto-generates one during key creation at `~/.gnupg/openpgp-revocs.d/<FINGERPRINT>.rev`. **Back this up off-machine** (password manager, offline storage). If you lose the YubiKey and this file, you can't revoke the key.

### Export public keys

```bash
# GPG public key (for GitHub, keyservers, etc.)
gpg --armor --export <FINGERPRINT>

# If you have multiple keys on the same UID, export by fingerprint
# to avoid bundling unrelated keys
gpg --armor --export <FINGERPRINT>
```

### Git signing

```bash
git config --global user.signingkey <FINGERPRINT>!
git config --global commit.gpgsign true
```

The `!` suffix forces GPG to use exactly that key.

### FIDO2 resident SSH key

This is a separate key from the OpenPGP auth subkey. The advantage: on a new machine, `ssh-keygen -K` pulls the key off the YubiKey without needing a GnuPG stack.

```bash
ssh-keygen -t ed25519-sk -O resident -O application=ssh:whatever
```

- `-O resident` stores the credential on the YubiKey itself
- `-O application=ssh:whatever` is a namespace label on the device to distinguish multiple resident keys -- it has **nothing to do with remote usernames**
- Add `-O verify-required` if you want FIDO2 PIN on every SSH connection (default is touch-only)
- The "private key" file on disk (`~/.ssh/id_ed25519_sk`) is just a handle; the real key never leaves the YubiKey

**Gotcha**: If you get `Key enrollment failed: invalid format`, check the verbose output (`-vvv`). It's almost certainly `FIDO_ERR_ACTION_TIMEOUT` -- you didn't touch the key fast enough after entering the PIN. The error message is misleading.

Recover the key on a new machine:

```bash
ssh-keygen -K
```

### OATH/TOTP

The YubiKey stores TOTP seeds. Managed entirely through ykman:

```bash
ykman oath accounts add -t <issuer> <secret>   # -t = require touch
ykman oath accounts code <issuer>               # generate code
```

### Optional: yubikey-touch-detector

Pops a desktop notification when the YubiKey is waiting for a tap. Saves you from staring at a blinking LED wondering if your machine crashed.

```bash
pacman -S yubikey-touch-detector
systemctl --user enable --now yubikey-touch-detector.service
```

---

## Part 2: PAM Authentication

This replaces password authentication with the YubiKey for login and sudo. [pam-u2f docs](https://developers.yubico.com/pam-u2f/), [ArchWiki](https://wiki.archlinux.org/title/Universal_2nd_Factor)

### Install and register

```bash
pacman -S pam-u2f
mkdir -p ~/.config/Yubico
pamu2fcfg -u $USER > ~/.config/Yubico/u2f_keys
```

Touch the key when it blinks. To register a backup key, **append**:

```bash
pamu2fcfg -u $USER >> ~/.config/Yubico/u2f_keys
```

#### The `-N` flag and PIN behaviour

`pamu2fcfg -N` registers the credential with PIN verification **baked into the FIDO2 credential itself**. This means the authenticator will demand a PIN regardless of what the PAM config says -- including `pinverification=0`.

If you want different PIN behaviour for different contexts (touch-only for login, PIN for sudo), register **without** `-N` and control it purely through the PAM line:

- `pinverification=1` -- PAM requests PIN from the authenticator at auth time
- `pinverification=0` -- PAM explicitly skips PIN
- Omitted -- falls back to "authenticator default" (which is PIN-required if the credential was registered with `-N`)

### PAM configuration

The auth chain on Arch: individual services → `system-login` → `system-auth`. Add the U2F line as `sufficient` before the existing `auth` lines so it's tried first, falling through to password if the key isn't present.

**`/etc/pam.d/system-login`** (covers local login, SDDM, SSH):

```
auth      sufficient  pam_u2f.so  cue pinverification=0
```

Add this as the **first** `auth` line, before `auth include system-auth`. The `cue` option prints "Please touch the device" so you know to tap.

**`/etc/pam.d/sudo`** (escalation, with PIN):

```
auth      sufficient  pam_u2f.so  cue pinverification=1
```

Again, first `auth` line, before `auth include system-auth`.

**`/etc/pam.d/polkit-1`** (systemctl, KDE admin prompts -- create this file if it doesn't exist):

```
#%PAM-1.0
auth        sufficient      pam_u2f.so cue pinverification=1
auth        include         system-auth
account     include         system-auth
session     include         system-auth
```

### Testing

**Keep a root shell open on a separate TTY before touching PAM files.** If you break PAM, this is your only way back in.

1. Edit `/etc/pam.d/sudo` first, test with `sudo echo works`
2. Then `/etc/pam.d/system-login`, test login on another TTY
3. If the key isn't plugged in, `sufficient` means it falls through to password -- verify this too

### Disable password for your account

Once the YubiKey is the sole auth method:

```bash
sudo passwd -l $USER
```

This prepends `!` to the password hash in `/etc/shadow`. Password auth fails; U2F still works because `pam_u2f.so` is `sufficient` and comes before `pam_unix.so`. Reverse with `sudo passwd -u $USER`.

`pam_faillock` can't lock you out of YubiKey auth -- when `pam_u2f.so` succeeds as `sufficient`, PAM returns immediately and never reaches the faillock modules.

### Auto-lock on removal

Create `/etc/udev/rules.d/80-yubikey-lock.rules`:

```
ACTION=="remove", ENV{ID_VENDOR_ID}=="1050", RUN+="/usr/bin/loginctl lock-sessions"
```

`1050` is Yubico's vendor ID. Pipe-delimit for multiple vendors: `"1050|20a0"` (Nitrokey is `20a0`).

Reload: `sudo udevadm control --reload`. Takes effect on next removal.

`loginctl lock-sessions` locks **all** GUI sessions on the machine.

---

## Part 3: LUKS Full Disk Encryption with FIDO2

This is real challenge-response, not a static password trick. The YubiKey generates a hardware-bound secret (`CredRandom`) that never leaves the secure element. At unlock time, the host and YubiKey do an ECDH key exchange, the host sends a random salt, and the YubiKey computes `HMAC-SHA256(CredRandom, salt)`. The result unlocks the LUKS key slot. Without the YubiKey, the slot is cryptographically inaccessible. [Poettering's writeup](https://0pointer.net/blog/unlocking-luks2-volumes-with-tpm2-fido2-pkcs11-security-hardware-on-systemd-248.html), [Yubico hmac-secret docs](https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html)

### Requirements

- **LUKS2** (not LUKS1). Check with `lsblk -f` -- the `FSVER` column shows the version. Convert with `cryptsetup convert /dev/sdX --type luks2` (in-place header conversion, not re-encryption, but back up the header first: `cryptsetup luksHeaderBackup /dev/sdX --header-backup-file luks.bak`)
- **systemd 248+** (you have this)
- **libfido2** (`pacman -S libfido2`)
- The `sd-encrypt` initramfs hook (systemd-based), not the legacy `encrypt` hook

### Enrollment

```bash
# Back up the LUKS header first
sudo cryptsetup luksHeaderBackup /dev/nvme0n1pX --header-backup-file ~/luks-header.bak

# Generate a recovery key (print this, store offline)
sudo systemd-cryptenroll --recovery-key /dev/nvme0n1pX

# Enroll the YubiKey
sudo systemd-cryptenroll --fido2-device=auto /dev/nvme0n1pX
```

This prompts for the existing LUKS passphrase, then the FIDO2 PIN, then a touch. Both PIN and touch are enforced by default. To change this:

- `--fido2-with-client-pin=yes|no`
- `--fido2-with-user-presence=yes|no`

[systemd-cryptenroll(1)](https://man.archlinux.org/man/systemd-cryptenroll.1.en)

### Initramfs configuration

#### dracut (EndeavourOS, Fedora, etc.)

If you're already using `rd.luks.uuid=` in your kernel cmdline and dracut, you likely already have the systemd-based unlock path. Verify with `cat /proc/cmdline` -- if you see `rd.luks.uuid=`, you're set.

Regenerate initramfs after enrollment:

```bash
sudo dracut --force
```

#### mkinitcpio (vanilla Arch)

Replace the `encrypt` hook with `sd-encrypt` in `/etc/mkinitcpio.conf`:

```
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
```

Add to `/etc/crypttab.initramfs`:

```
luks  /dev/nvme0n1pX  -  fido2-device=auto
```

Regenerate:

```bash
sudo mkinitcpio -P
```

### Boot flow

At boot: PIN prompt appears → enter FIDO2 PIN → touch the YubiKey (it blinks, no on-screen prompt) → disk unlocked. If no YubiKey is present, it falls back to the password/recovery key prompt.

LUKS2 supports up to 32 key slots. You can have your original password, a FIDO2 credential, and a recovery key all active simultaneously.

### Wipe a slot

```bash
# List tokens
sudo systemd-cryptenroll /dev/nvme0n1pX

# Remove a specific slot
sudo systemd-cryptenroll --wipe-slot=<slot-number> /dev/nvme0n1pX
```

---

## Quick Reference

| What | Where |
|------|-------|
| scdaemon config | `~/.gnupg/scdaemon.conf` |
| gpg-agent config | `~/.gnupg/gpg-agent.conf` |
| gpg config | `~/.gnupg/gpg.conf` |
| Revocation cert | `~/.gnupg/openpgp-revocs.d/<FPR>.rev` |
| FIDO2 SSH key | `~/.ssh/id_ed25519_sk` + `id_ed25519_sk.pub` |
| U2F credentials | `~/.config/Yubico/u2f_keys` |
| PAM login | `/etc/pam.d/system-login` |
| PAM sudo | `/etc/pam.d/sudo` |
| PAM polkit | `/etc/pam.d/polkit-1` |
| Auto-lock udev rule | `/etc/udev/rules.d/80-yubikey-lock.rules` |
| Default PINs (after reset) | user: `123456`, admin: `12345678` |
| Restart scdaemon | `gpgconf --kill scdaemon && gpgconf --kill gpg-agent` |
| Recover SSH key on new machine | `ssh-keygen -K` |
| Touch notification daemon | `yubikey-touch-detector` |
