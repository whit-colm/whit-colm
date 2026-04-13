---
title: "Building 'Gertrude'"
description: "Full disk encryption with FIDO2 + TPM2 + Secure Boot on EndeavourOS -- disk layout, UKI boot chain, keyfile cascade, and the rest of the desktop setup."
summary: "Technical reference for building a locked-down Linux desktop: FIDO2 root unlock, TPM2 swap, Secure Boot with custom keys, UKIs, and automated maintenance."
author: ["Whit Huntley"]
date: "2026-01-14T14:30:00-05:00"
lastmod: "2026-04-13T00:00:00-04:00"
draft: true
links-as-notes: true
papersize: A4
showReadingTime: true
tags: ["relevant"]
---

Goals:
- Put all effort in up-front
- Childproofing: backups so no forever-breaking, automate what can be automated
- Multi-ish user: I will need not infrequent access for support
- Make good choices I can copy for future builds

This post is a reference card for recreating the setup on a fresh [EndeavourOS](https://endeavouros.com/) install with LUKS encryption. It documents the delta from what Calamares gives you out of the box -- if something isn't mentioned here, it's stock.

## Hardware

| Component | Detail |
|-----------|--------|
| Motherboard | ASUS ROG STRIX X870-I GAMING WIFI |
| BIOS | 1022 (2025-03-05) |
| CPU | AMD Ryzen 7 9800X3D |
| RAM | 2x DDR5 |
| NVMe | 1TB (867G root + 64G swap + 512M ESP) |
| SATA SSD | 3.6TB (external data drive) |
| Recovery USB | Internal USB port, EndeavourOS ISO `dd`'d |

BIOS settings that matter (ASUS-specific, see [Secure Boot](#secure-boot)):

| Setting | Path | Value |
|---------|------|-------|
| OS Type | Boot > Secure Boot | Windows UEFI mode |
| Secure Boot Mode | Security > Secure Boot | Custom |
| Fast Boot | Boot > Fast Boot | Disabled |
| TPM | Advanced > Trusted Computing | Enabled |

## Disk Layout

### Partitions

| Partition | Size | Type | LUKS UUID | Mapper Name | Mount |
|-----------|------|------|-----------|-------------|-------|
| `nvme0n1p3` | 512M | EFI (vfat) | -- | -- | `/efi` |
| `nvme0n1p1` | 867G | LUKS2 > btrfs | `7d30eecb-e787-49d6-9dff-5429acbe42a0` | `root_crypt` | `/` |
| `nvme0n1p2` | 64G | LUKS2 > swap | `dedaf47c-9eb7-4003-aae3-a9b27aa7cc79` | `swap_crypt` | swap |
| `sda1` | 3.6T | LUKS2 > btrfs | `f4d051fb-eaad-40d6-8391-1cc70f19c911` | `data_crypt` | `/opt/backups`, `/opt/bulkstore` |

### Btrfs Subvolumes

Root drive (`root_crypt`):

| Subvolume | Mount | Compression | Notes |
|-----------|-------|-------------|-------|
| `@` | `/` | `zstd` (default level) | |
| `@home` | `/home` | `zstd` | |
| `@snapshots` | `/.snapshots` | `zstd:15` | Max compression, rarely written |
| `@cache` | `/var/cache` | `zstd:5` | Moderate -- pacman cache is big |
| `@log` | `/var/log` | `zstd:15` | |
| `@games` | `/opt/steam-library` | `zstd:8` | Balance between size and load times |

Data drive (`data_crypt`):

| Subvolume | Mount | Compression |
|-----------|-------|-------------|
| `@backup` | `/opt/backups` | `compress-force=zstd:15` |
| `@bulkstore` | `/opt/bulkstore` | `compress-force=zstd:15` |

`compress-force` on the data drive because we're optimising for density over speed. The root drive uses `compress` (advisory) so incompressible data isn't wasted on.

### LUKS Configuration

```
# /etc/crypttab
root_crypt  UUID=7d30eecb-e787-49d6-9dff-5429acbe42a0  none  luks,fido2-device=auto,discard,no-read-workqueue,no-write-workqueue
swap_crypt  UUID=dedaf47c-9eb7-4003-aae3-a9b27aa7cc79  none  luks,tpm2-device=auto,x-initrd.attach,nofail,discard,no-read-workqueue,no-write-workqueue
data_crypt  UUID=f4d051fb-eaad-40d6-8391-1cc70f19c911  /etc/cryptsetup-keys.d/gertrude.key  luks,noauto,nofail,discard
```

What the options mean:

- **`fido2-device=auto`** -- unlock via FIDO2 challenge-response (YubiKey). PIN + touch required.
- **`tpm2-device=auto`** -- unlock via TPM2. No user interaction.
- **`x-initrd.attach`** -- unlock this device in the initramfs (early boot), not after root is mounted. Required for swap because the resume-from-hibernation check needs swap available before root's systemd takes over.
- **`nofail`** -- don't block boot if this device fails to unlock. Swap and data are nice-to-have, not boot-critical.
- **`noauto`** -- don't try to unlock during early boot at all. Data drive is late-boot only (needs the keyfile from root).
- **`discard,no-read-workqueue,no-write-workqueue`** -- performance: TRIM passthrough, bypass dm-crypt's internal workqueues (faster on NVMe/SSD).

LUKS key slots:

| Device | Slot 0 | Slot 1 | Slot 3 |
|--------|--------|--------|--------|
| `root_crypt` | password | recovery key | FIDO2 (YubiKey) |
| `swap_crypt` | password | recovery key | TPM2 (PCR 7) |
| `data_crypt` | password | -- | keyfile |

### Keyfile

For the data drive only. Swap used to use this keyfile too; it now uses TPM2.

```bash
dd if=/dev/urandom of=/etc/cryptsetup-keys.d/gertrude.key bs=4096 count=1 status=none
chown root:root /etc/cryptsetup-keys.d/gertrude.key
chmod 0400 /etc/cryptsetup-keys.d/gertrude.key
```

Then enroll it on the LUKS volume:

```bash
cryptsetup luksAddKey /dev/disk/by-uuid/f4d051fb-eaad-40d6-8391-1cc70f19c911 /etc/cryptsetup-keys.d/gertrude.key
```

### fstab

```fstab
# /etc/fstab
UUID=00F5-06B3          /efi                vfat    fmask=0137,dmask=0027,nosuid,nodev,noexec                   0 2
/dev/mapper/root_crypt  /                   btrfs   subvol=/@,noatime,discard=async,compress=zstd                0 0
/dev/mapper/root_crypt  /home               btrfs   subvol=/@home,noatime,discard=async,compress=zstd            0 0
/dev/mapper/root_crypt  /.snapshots         btrfs   subvol=/@snapshots,noatime,discard=async,compress=zstd:15    0 0
/dev/mapper/root_crypt  /var/cache          btrfs   subvol=/@cache,noatime,discard=async,compress=zstd:5         0 0
/dev/mapper/root_crypt  /var/log            btrfs   subvol=/@log,noatime,discard=async,compress=zstd:15          0 0
/dev/mapper/root_crypt  /opt/steam-library  btrfs   subvol=/@games,noatime,discard=async,compress=zstd:8         0 0
/dev/mapper/swap_crypt  swap                swap    defaults                                                     0 0
/dev/mapper/data_crypt  /opt/backups        btrfs   subvol=/@backup,noatime,compress-force=zstd:15,nofail        0 0
/dev/mapper/data_crypt  /opt/bulkstore      btrfs   subvol=/@bulkstore,noatime,compress-force=zstd:15,nofail     0 0
tmpfs                   /tmp                tmpfs   defaults,noatime,mode=1777                                   0 0
```

## Boot Chain

### What You Start With

A fresh EndeavourOS install with LUKS encryption gives you: systemd-boot with Type #1 boot entries (separate kernel, initrd, and `.conf` files in `/efi/loader/entries/`), dracut for initramfs generation, the `kernel-install-for-dracut` package handling kernel updates, and a single password prompt to unlock root. No Secure Boot, no TPM2, no FIDO2. Swap unlocks via a keyfile baked into the initramfs by Calamares.

### What We're Building

1. UEFI firmware validates Secure Boot signatures
2. systemd-boot (signed) auto-discovers UKIs in `/efi/EFI/Linux/`
3. User selects an entry (4 options: mainline, mainline-fallback, LTS, LTS-fallback)
4. UKI loads -- kernel, initramfs, and cmdline are all inside the one `.efi` file
5. FIDO2 prompt for `root_crypt` -- user enters PIN, touches YubiKey
6. Root unlocks, systemd continues
7. TPM2 auto-unseals `swap_crypt` (PCR 7 validated, no user interaction)
8. Keyfile at `/etc/cryptsetup-keys.d/gertrude.key` unlocks `data_crypt`
9. All filesystems mount, boot completes

### Unified Kernel Images

A UKI bundles the kernel, initramfs, and boot parameters into a single `.efi` binary. Secure Boot signs one file instead of trusting a chain of unsigned components.

```
# /etc/kernel/install.conf
layout=uki
initrd_generator=dracut
uki_generator=dracut
```

This tells `kernel-install` to produce UKIs instead of Type #1 entries. The kernel command line embedded in the UKI comes from:

```
# /etc/kernel/cmdline
nvme_load=YES rw rootflags=subvol=/@ rd.luks.uuid=7d30eecb-e787-49d6-9dff-5429acbe42a0 root=/dev/mapper/root_crypt
```

**Gotcha**: Only `rd.luks.uuid` here, not `rd.luks.name`. Having both `rd.luks.name=...=root_crypt` in the cmdline and `root_crypt` in crypttab triggers a [dracut bug](https://github.com/dracutdevs/dracut/issues/2512) that concatenates the names with a space, producing a mangled unit name like `systemd-cryptsetup@root_crypt\x20root_crypt.service`. The crypttab provides the name and options; the cmdline just needs the UUID to activate the device in the initrd.

**Gotcha**: No `resume=` in the cmdline. See [Hibernation](#hibernation).

### dracut Configuration

```
# /etc/dracut.conf.d/calamares-luks.conf
# Originally written by Calamares. Gutted -- it force-included all LUKS
# devices and the keyfile into the initramfs, which conflicts with
# per-device unlock (FIDO2/TPM2/keyfile cascade).
```

Calamares creates this file with `install_items+=" /etc/crypttab /crypto_keyfile.bin "` and `add_device+=" /dev/disk/by-uuid/... "` for every LUKS partition. That pulls swap and data into the initramfs where they don't belong. Gut it.

```
# /etc/dracut.conf.d/eos-defaults.conf (stock, no changes needed)
omit_dracutmodules+=" network cifs nfs nbd brltty "
compress="zstd"
```

```
# /etc/dracut.conf.d/resume.conf
add_dracutmodules+=" resume "
```

Adds the `resume` dracut module for hibernation support. Without this, the initramfs won't check for a hibernation image.

```
# /etc/dracut.conf.d/uki-cmdline.conf
kernel_cmdline="$(cat /etc/kernel/cmdline 2>/dev/null)"
```

**This file is critical.** dracut does NOT read `/etc/kernel/cmdline` for UKI cmdline embedding[^1]. It only uses the `--kernel-cmdline` CLI argument or the `kernel_cmdline=` variable in `dracut.conf`. This bridge file feeds the cmdline into dracut so automated builds (via `kernel-install`) embed the correct parameters. Without it, UKIs get built with an empty `.cmdline` section and root won't unlock.

[^1]: Verified by grepping the entire dracut source tree. The man page implies it reads `/etc/kernel/cmdline` but it doesn't -- only `systemd-stub` reads it at boot time, and that's irrelevant for UKIs where the cmdline is baked in at build time.

Because `uki-cmdline.conf` handles the cmdline, do **not** also pass `--kernel-cmdline` when calling dracut manually -- you'll get the parameters doubled in the UKI.

### Kernel Install Hook

`kernel-install-for-dracut` is an EndeavourOS package that manages kernel updates for systemd-boot. It works fine with Type #1 entries but doesn't know about UKIs or fallback images. Remove it and replace with a custom hook:

```bash
# kernel-install-for-dracut is a HoldPkg -- needs confirmation
yes | pacman -R kernel-install-for-dracut
```

Before removing, save its pacman hooks (the hook files, not the package's install.d scripts). The hooks trigger on kernel/firmware/dkms changes and call a script. We keep the hooks but point them at our own script.

**`/etc/pacman.d/hooks/90-kernel-install.hook`**:

```ini
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Operation = Remove
Target = usr/lib/dracut/*
Target = usr/lib/firmware/*
Target = usr/src/*/dkms.conf

[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Operation = Remove
Target = systemd

[Action]
Description = Running kernel-install...
When = PostTransaction
Exec = /usr/local/lib/kernel-install-hook add
NeedsTargets
```

**`/etc/pacman.d/hooks/90-kernel-remove.hook`**:

```ini
[Trigger]
Type = Path
Operation = Remove
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Removing kernel...
When = PreTransaction
Exec = /usr/local/lib/kernel-install-hook remove
NeedsTargets
```

**`/etc/pacman.d/hooks/systemd-boot.hook`**:

```ini
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot
When = PostTransaction
Exec = /usr/bin/bootctl update --no-variables --graceful
```

**`/usr/local/lib/kernel-install-hook`**:

```bash
#!/usr/bin/env bash

generate_fallback() {
    local version="$1"
    local action="$2"
    local fallback="/efi/EFI/Linux/endeavouros-${version}-fallback.efi"

    if [[ "$action" == "add" ]]; then
        echo ":: Generating fallback UKI for ${version}"
        dracut --force --uefi --no-hostonly \
            "$fallback" "$version"
        if command -v sbctl &>/dev/null; then
            sbctl sign -s "$fallback"
        fi
    elif [[ "$action" == "remove" ]]; then
        echo ":: Removing fallback UKI for ${version}"
        rm -f "$fallback"
        if command -v sbctl &>/dev/null; then
            sbctl remove-file "$fallback" 2>/dev/null
        fi
    fi
}

while read -r line; do
    if [[ $line != */vmlinuz ]]; then
        all=1
    fi

    [[ $all == 1 ]] && continue

    version=$(basename "${line%/vmlinuz}")
    if [[ $1 == "remove" ]]; then
        echo ":: kernel-install removing kernel $version"
        kernel-install remove "${version}"
        generate_fallback "$version" "remove"
    elif [[ $1 == "add" ]]; then
        echo ":: kernel-install installing kernel $version"
        kernel-install add "${version}" "${line}"
        generate_fallback "$version" "add"
    else
        echo ":: Invalid option passed to kernel-install script"
    fi
done

if [[ $all == 1 ]]; then
    while read -r kernel; do
        kernelversion=$(basename "${kernel%/vmlinuz}")
        echo "Running kernel-install for ${kernelversion}"
        kernel-install add "${kernelversion}" "${kernel}"
        generate_fallback "$kernelversion" "add"
    done < <(find /usr/lib/modules -maxdepth 2 -type f -name vmlinuz)
fi

if [ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]; then
    echo 'Running in a chroot, skipping cmdline generation'
    exit 0
fi

if [[ ! -e /etc/kernel/cmdline ]]; then
    mkdir -p /etc/kernel
    BOOT_OPTIONS=""
    read -r -d '' -a line < /proc/cmdline
    for i in "${line[@]}"; do
        [[ "${i#initrd=*}" != "$i" ]] && continue
        [[ "${i#BOOT_IMAGE=*}" != "$i" ]] && continue
        [[ "${i#systemd.machine_id=*}" != "$i" ]] && continue
        BOOT_OPTIONS+="$i "
    done
    echo "${BOOT_OPTIONS}" > /etc/kernel/cmdline
fi
```

`kernel-install add` produces the normal (hostonly) UKI via dracut. `generate_fallback()` then runs dracut again with `--no-hostonly` (all modules included) for a generic fallback UKI, and signs it with sbctl. The result is 4 UKIs in `/efi/EFI/Linux/`: normal + fallback for each installed kernel.

sbctl's own `/usr/lib/kernel/install.d/91-sbctl.install` auto-signs the normal UKI that `kernel-install` produces. The hook script signs the fallback UKI explicitly since it's generated outside `kernel-install`.

### Secure Boot

EndeavourOS doesn't support Secure Boot out of the box. The ISO is unsigned and the installer doesn't set up keys. This is a post-install addition.

```bash
pacman -S sbctl
sbctl create-keys
sbctl enroll-keys -m
```

The `-m` flag includes Microsoft's UEFI CA certificates in the key database. This is required -- without it, the board's option ROMs (GPU, NIC) and firmware components signed by Microsoft won't load, potentially bricking the boot process.

Sign everything:

```bash
sbctl sign -s /efi/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /efi/EFI/BOOT/BOOTX64.EFI
# UKIs are signed by the kernel-install hook and sbctl's install.d script
sbctl verify
```

The `-s` flag registers files in sbctl's database so future `sbctl sign-all` calls re-sign them.

**ASUS-specific BIOS configuration:**

The ASUS ROG STRIX X870-I doesn't have a straightforward "Secure Boot: On/Off" toggle. Instead:

1. **Security > Secure Boot > Secure Boot Mode > Custom** -- "Standard" only accepts Microsoft's default key hierarchy. "Custom" allows your sbctl-enrolled keys.
2. **Boot > Secure Boot > OS Type > Windows UEFI mode** -- despite the name, this is the Secure Boot enforcement toggle. "Other OS" = Secure Boot disabled. Yes, it's stupid.

Verify from Linux:

```bash
sbctl status
# Should show: Setup Mode: Disabled, Secure Boot: Enabled
```

**BIOS updates clear Secure Boot keys.** After a firmware update, re-enroll with `sbctl enroll-keys -m` and re-sign with `sbctl sign-all`. The BIOS needs to be in Setup Mode first -- clear the keys in Key Management if it isn't.

**The EndeavourOS live ISO is unsigned.** To boot a recovery USB with Secure Boot enabled, toggle Secure Boot off in the BIOS first. This does NOT clear your enrolled keys -- they're preserved in NVRAM, just unenforced. Toggle it back on after recovery.

### FIDO2 Unlock (root_crypt)

Enrollment is covered in the [YubiKey post](/posts/yubikey/#part-3-luks-full-disk-encryption-with-fido2). The short version:

```bash
systemd-cryptenroll --fido2-device=auto /dev/disk/by-uuid/7d30eecb-e787-49d6-9dff-5429acbe42a0
```

The crypttab option `fido2-device=auto` tells `systemd-cryptsetup` to attempt FIDO2 unlock at boot. The boot-time UX: FIDO2 PIN prompt appears, enter PIN, touch the YubiKey when it blinks, root unlocks. If no YubiKey is present, it times out and falls back to the password/recovery key prompt.

Why FIDO2 for root: physical presence is required. The key never leaves the YubiKey's secure element. An attacker with the disk but not the key gets nothing. An attacker who steals the key but doesn't know the PIN also gets nothing.

### TPM2 Unlock (swap_crypt)

```bash
pacman -S tpm2-tools
```

`tpm2-tools` is required by dracut's `tpm2-tss` module. Without it, the module's `module-setup.sh` fails the `require_binaries tpm2` check and won't be included in the initramfs.

```bash
systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=7 \
  /dev/disk/by-uuid/dedaf47c-9eb7-4003-aae3-a9b27aa7cc79
```

PCR 7 measures the Secure Boot policy -- the full chain of trust from firmware through the boot loader. If the boot chain is tampered with (unsigned kernel, modified bootloader, Secure Boot disabled), the PCR value changes, the TPM refuses to unseal, and swap stays locked.

Why TPM2 for swap instead of FIDO2: swap needs to unlock without user interaction. It holds hibernation images that must be accessible before the user has a chance to touch anything. TPM2 gives hardware-bound security (via Secure Boot policy) without requiring a keypress.

The `x-initrd.attach` option in crypttab ensures swap unlocks in the initramfs, early enough for the hibernation resume check. `nofail` ensures a TPM2 failure (e.g., after a firmware update that changed PCR values) doesn't brick the boot -- it falls back to the password prompt and continues without swap.

**TPM2 PCR values change after BIOS/firmware updates** (just like Secure Boot keys). Re-enroll swap after firmware changes:

```bash
systemd-cryptenroll \
  --wipe-slot=tpm2 \
  --tpm2-device=auto \
  --tpm2-pcrs=7 \
  /dev/disk/by-uuid/dedaf47c-9eb7-4003-aae3-a9b27aa7cc79
```

### Keyfile Cascade (data_crypt)

The keyfile lives at `/etc/cryptsetup-keys.d/gertrude.key` on the root filesystem. Root must be unlocked first (via FIDO2) before the keyfile is accessible -- so `data_crypt` is gated on `root_crypt` by construction.

The `noauto` option means systemd won't try to unlock `data_crypt` during early boot. `nofail` means it won't block boot if the external drive is unplugged. systemd picks it up when it processes crypttab entries after root is mounted and the keyfile is available.

### Hibernation

The `resume` dracut module (in `resume.conf`) enables hibernation support in the initramfs. But there's no `resume=/dev/mapper/swap_crypt` in the kernel cmdline. Instead, we rely on systemd's `HibernateLocation` EFI variable.

On systemd 252+, when you run `systemctl hibernate`, systemd writes the resume device location to an EFI variable. On the next boot, `systemd-hibernate-resume-generator` reads this variable and attempts resume with a built-in 2-minute timeout. If you didn't hibernate, the variable doesn't exist and resume is skipped entirely.

**Gotcha**: A `resume=` parameter in the kernel cmdline causes `systemd-hibernate-resume-generator` to set `JobTimeoutSec=infinity` on the swap device. If TPM2 fails to unseal (e.g., after a firmware update), the boot hangs forever waiting for `/dev/mapper/swap_crypt` to appear. The `nofail` option in crypttab is irrelevant -- the resume dependency overrides it. The `HibernateLocation` EFI variable approach avoids this entirely.

Test with `systemctl hibernate`. The system should write the image to swap, power off, and resume on the next boot without any user interaction beyond the FIDO2 prompt for root.

## Security Posture

| Layer | Mechanism | Protects Against |
|-------|-----------|-----------------|
| Root volume | FIDO2 (YubiKey) | Disk theft, evil maid (requires physical key + PIN) |
| Swap volume | TPM2 (PCR 7) | Hibernation data extraction, boot chain tampering |
| Data volume | Keyfile on encrypted root | Can't access without unlocking root first |
| Boot chain | Secure Boot (custom + Microsoft keys) | Unsigned/tampered bootloaders, kernel, initramfs |
| UKIs | Signed bundle | Prevents mixing a valid kernel with a tampered initramfs or cmdline |

What this does NOT protect against:
- **Cold boot attacks** -- RAM contents persist briefly after power off. Use `mem_sleep_default=deep` if paranoid.
- **DMA attacks** -- Thunderbolt/PCIe devices can read memory. IOMMU helps but isn't a guarantee.
- **Compromised firmware updates** -- If ASUS pushes a malicious BIOS update, all bets are off. Secure Boot trusts the firmware implicitly.
- **Rubber hose cryptanalysis** -- the YubiKey has a PIN, not a dead man's switch.

## Backups

You're gonna need to build this, asshole.

## Networking

### WoL

[Wake on LAN](https://wiki.archlinux.org/title/Wake-on-LAN):

```
# /etc/udev/rules.d/90-wol.rules
ACTION=="add", SUBSYSTEM=="net", NAME=="en*" RUN+="/usr/bin/ethtool -s $name wol ug"
```

### Reflector

Enable timer, customise conf:

```bash
/usr/bin/reflector @/etc/xdg/reflector/reflector.conf && [ -s /etc/pacman.d/mirrorlist.new ] && cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.old && mv /etc/pacman.d/mirrorlist.new /etc/pacman.d/mirrorlist
```

## System Automation

### Auto-Recovery Disk

Put tiny USB stick in spare USB port, on systemd timer pull latest image, verify against signature (how? signing key?)

udev rules to hide it from removable storage.

### Auto-Timezone

```sh
#!/bin/sh
#
# NetworkManager dispatcher script to automatically set timezone based on geolocation
# Place in: /etc/NetworkManager/dispatcher.d/10-auto-timezone
# Make executable: chmod 755 /etc/NetworkManager/dispatcher.d/10-auto-timezone
#
# This script:
# - Runs on non-VPN network connections only
# - Uses connectivity-change event to avoid triggering on VPN connections
# - Falls back to 'up' event with VPN detection as backup
# - Includes error handling and logging
# - Fully POSIX compliant
#

INTERFACE="$1"
ACTION="$2"

# Logging function (logs to journal)
log() {
    logger -t "auto-timezone" "$@"
}

# Check if this is a VPN connection using multiple detection methods
# Returns 0 (true) if VPN detected, 1 (false) otherwise
is_vpn() {
    # Method 1: Check if VPN_IP_IFACE environment variable is set
    # This is set by NetworkManager for all VPN connections
    if [ -n "$VPN_IP_IFACE" ]; then
        log "VPN detected via VPN_IP_IFACE: $VPN_IP_IFACE"
        return 0
    fi
    
    # Method 2: Check connection type via CONNECTION_ID
    # VPN connections often have identifiable names
    # Note: Use case-insensitive grep with multiple patterns
    case "$CONNECTION_ID" in
        *vpn*|*VPN*|*proton*|*Proton*|*wireguard*|*WireGuard*|*openvpn*|*OpenVPN*|*pptp*|*PPTP*|*l2tp*|*L2TP*)
            log "VPN detected via CONNECTION_ID pattern: $CONNECTION_ID"
            return 0
            ;;
    esac
    
    # Method 3: Check interface name patterns
    # Common VPN interface names: tun*, wg*, ppp*, proton*
    case "$INTERFACE" in
        tun*|wg*|ppp*|proton*)
            log "VPN detected via interface pattern: $INTERFACE"
            return 0
            ;;
    esac
    
    # Method 4: Check via nmcli for the specific connection UUID
    # This queries NetworkManager directly for the connection type
    if [ -n "$CONNECTION_UUID" ]; then
        is_vpn_conn_type=$(nmcli -t -f connection.type connection show "$CONNECTION_UUID" 2>/dev/null)
        case "$is_vpn_conn_type" in
            *vpn*|*wireguard*|*tun*)
                log "VPN detected via nmcli connection type: $is_vpn_conn_type"
                return 0
                ;;
        esac
    fi
    
    return 1
}

# Update timezone function
# Returns 0 on success, 1 on failure
update_timezone() {
    log "Attempting to update timezone for interface: $INTERFACE (action: $ACTION)"
    
    # Fetch timezone from geolocation API
    update_tz_new_tz=$(curl --fail --silent --max-time 10 https://ipapi.co/timezone 2>&1)
    update_tz_curl_exit=$?
    
    if [ $update_tz_curl_exit -ne 0 ]; then
        log "Failed to fetch timezone from ipapi.co (exit code: $update_tz_curl_exit)"
        return 1
    fi
    
    if [ -z "$update_tz_new_tz" ]; then
        log "Empty timezone returned from API"
        return 1
    fi
    
    # Get current timezone
    update_tz_current_tz=$(timedatectl show -p Timezone --value 2>/dev/null)
    
    # Only update if different
    if [ "$update_tz_new_tz" = "$update_tz_current_tz" ]; then
        log "Timezone already set to $update_tz_new_tz, no change needed"
        return 0
    fi
    
    # Set the new timezone
    if timedatectl set-timezone "$update_tz_new_tz" 2>&1; then
        log "Successfully updated timezone from $update_tz_current_tz to $update_tz_new_tz"
        return 0
    else
        log "Failed to set timezone to $update_tz_new_tz"
        return 1
    fi
}

# Main logic
case "$ACTION" in
    connectivity-change)
        # connectivity-change is preferred because it fires when internet
        # connectivity is established, but NOT when VPNs connect
        # (VPNs use vpn-up/vpn-down events instead)
        
        # Only proceed if we have full connectivity
        if [ "$CONNECTIVITY_STATE" = "FULL" ]; then
            log "Connectivity changed to FULL, checking for VPN"
            
            # Extra safety check - ensure this isn't a VPN
            if ! is_vpn; then
                update_timezone
            else
                log "Skipping timezone update - VPN connection detected"
            fi
        fi
        ;;
        
    up)
        # Fallback to 'up' event with explicit VPN checking
        # This handles cases where connectivity-change might not fire
        
        log "Interface up event, checking for VPN"
        
        # Skip if this is a VPN connection
        if is_vpn; then
            log "Skipping timezone update - VPN connection detected"
            exit 0
        fi
        
        # Skip loopback interface
        if [ "$INTERFACE" = "lo" ]; then
            log "Skipping loopback interface"
            exit 0
        fi
        
        # Add a small delay to ensure network is fully ready
        sleep 2
        
        update_timezone
        ;;
        
    vpn-up)
        # Explicitly ignore VPN up events
        log "VPN connection established, skipping timezone update"
        ;;
        
    *)
        # Ignore other events
        ;;
esac

exit 0
```

## Windows Dual Boot

### Timezone

Open `regedit` and add a `DWORD` value with hexadecimal value `1` to the registry `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\TimeZoneInformation\RealTimeIsUniversal`

In administrator command prompt:

```
reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f
```

### Bluetooth

### Linux Access to Windows Partition

Disable fast startup to prevent corruption:

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power\" -Name "HiberbootEnabled" -Value "0"
```

Put the backup key somewhere you can access on the Linux side.

Create group, mountpoint:

```bash
mkdir /Windows
groupadd -g 11000 windows
usermod -aG windows kiki
```

Place the BitLocker backup key as `/etc/cryptsetup-keys.d/win.key` (`root:root`, `0400`), then add to crypttab:

```
bitlk-win-rootfs  UUID=<Windows-LUKS-UUID>  /etc/cryptsetup-keys.d/win.key  bitlk
```

And fstab:

```fstab
/dev/mapper/bitlk-win-rootfs  /Windows  ntfs3 uid=65534,gid=11000,fmask=0177,dmask=0077,noatime,trim,nocase,windows_names 0 0
```

## Quick Reference

### Files

| What | Where |
|------|-------|
| Kernel cmdline | `/etc/kernel/cmdline` |
| Kernel install config | `/etc/kernel/install.conf` |
| crypttab | `/etc/crypttab` |
| fstab | `/etc/fstab` |
| dracut LUKS config (gutted) | `/etc/dracut.conf.d/calamares-luks.conf` |
| dracut defaults (stock) | `/etc/dracut.conf.d/eos-defaults.conf` |
| dracut resume module | `/etc/dracut.conf.d/resume.conf` |
| dracut UKI cmdline bridge | `/etc/dracut.conf.d/uki-cmdline.conf` |
| Custom kernel-install hook | `/usr/local/lib/kernel-install-hook` |
| Pacman hook (kernel install) | `/etc/pacman.d/hooks/90-kernel-install.hook` |
| Pacman hook (kernel remove) | `/etc/pacman.d/hooks/90-kernel-remove.hook` |
| Pacman hook (bootctl update) | `/etc/pacman.d/hooks/systemd-boot.hook` |
| Data drive keyfile | `/etc/cryptsetup-keys.d/gertrude.key` |
| UKI output directory | `/efi/EFI/Linux/` |
| systemd-boot config | `/efi/loader/loader.conf` |
| WoL udev rule | `/etc/udev/rules.d/90-wol.rules` |
| Auto-timezone script | `/etc/NetworkManager/dispatcher.d/10-auto-timezone` |

### Packages (delta from fresh EndeavourOS)

| Action | Package | Why |
|--------|---------|-----|
| Install | `sbctl` | Secure Boot key management and signing |
| Install | `tpm2-tools` | TPM2 userspace; required by dracut's `tpm2-tss` module |
| Remove | `kernel-install-for-dracut` | Replaced by custom hook + upstream `kernel-install` |
