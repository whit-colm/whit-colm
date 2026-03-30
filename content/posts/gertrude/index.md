---
title: "Building 'Gertrude'"
description: "Linux Desktop Configuration for Future Builds"
summary: "Setting up a Linux daily driver for one of my girls."
author: ["Whit Huntley"]
date: 1768683440
draft: true
links-as-notes: true
papersize: A4
showReadingTime: false
tags: ["relevant"]
---

Goals:
- Put all effort in up-front
- Childproofing
  - Backups so no forever-breaking
  - Automate what can be automated
- Multi-ish user
  - I will need not infrequent access for support
- Make good choises I can copy for future builds

## Drives

Key creation necessary for swap and SATA SSD:

```sh
sudo dd if=/dev/urandom of=/etc/cryptsetup-keys.d/gertrude.key bs=4096 count=1 status=none \
  && chown root:root /etc/cryptsetup-keys.d/gertrude.key \
  && chmod 0400 /etc/cryptsetup-keys.d/gertrude.key
```

### External Drive

Subvolumes:

- Multi-user games
- Final resting place for backups

Using the key creation for LUKS, when we put btrfs on it we want to prioritize cramming as much as we can on there over speed.

## Backups

You're gonna need to build this, asshole.


## Yubikey Integration

Using it in place of password authentication

### Swap

The swap space is also encrypted, and with modifying the root filesystem's keys, this needed to be streamlined.

Add it to the drive, and remove all other keys.

Modify the crypttab and fstab

```fstab
swapfs  UUID=[UUID] /etc/cryptsetup-keys.d/gertrude.key luks
```

And then in the fstab:

```fstab
/dev/mapper/bitlk-win-rootfs  /Windows  ntfs3 uid=65534,gid=11000,fmask=0177,dmask=0077,noatime,trim,nocase,windows_names 0 0
```

## WoL

Enabling [Wake on LAN](https://wiki.archlinux.org/title/Wake-on-LAN) 

```rules
# /etc/udev/rules.d/90-wol.rules
ACTION=="add", SUBSYSTEM=="net", NAME=="en*" RUN+="/usr/bin/ethtool -s $name wol ug"
```

## Reflector

Roughly fine, enable timer, customize conf, edited oneliner:

```sh
/usr/bin/reflector @/etc/xdg/reflector/reflector.conf && [ -s /etc/pacman.d/mirrorlist.new ] && cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.old && mv /etc/pacman.d/mirrorlist.new /etc/pacman.d/mirrorlist
```

## Auto-Recovery Disk

Put tiny USB stick in spare USB port, on systemd timer pull latest image, verify against signature (how? signing key?)

udev rules to hide it from removable storage.

## Auto-timezone

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

## Windows

### Timezone

Open `regedit` and add a `DWORD` value with hexadecimal value `1` to the registry `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\TimeZoneInformation\RealTimeIsUniversal`

In administrator command prompt:

```
C:\>reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f
```

### Bluetooth

### Linux Access

Disable fast startup to prevent corruption:

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power\" -Name "HiberbootEnabled" -Value "0"
```

Put the backup key somewhere you can access on the Linux side.

#### Linux

Create group, mountpoint as superuser:

```sh
mkdir /Windows && \
  groupadd -g 11000 windows && \
  usermod -aG windows kiki
```

Place the backup key as `/etc/cryptsetup-keys.d/win.key` (making sure `root:root` ownership/`0400` perms), then add to the `/etc/crypttab`:

```fstab
bitlk-win-rootfs  UUID=[UUID] /etc/cryptsetup-keys.d/win.key  bitlk
```

And then in the fstab:

```fstab
/dev/mapper/bitlk-win-rootfs  /Windows  ntfs3 uid=65534,gid=11000,fmask=0177,dmask=0077,noatime,trim,nocase,windows_names 0 0
```