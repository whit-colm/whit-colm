---
title: "[Backend@Dotfile v3] Part 1 - First Install"
description: "Part 0 of docs reworking my Kubernetes Cluster"
summary: "Part 0 of docs reworking my Kubernetes Cluster"
date: 2022-06-26T11:59:15-05:00
draft: true
tags: ["bdv3", "kubernetes", "relevant"]
---

With my design outline done, I jumped headfirst into it.

# Initial setup

To begin, I first installed `talosctl`, the CLI tool which provides access to the machines and the `.iso` [installer for amd64](https://github.com/siderolabs/talos/releases/download/v1.1.0/talos-amd64.iso), `dd`'d it, all that goodness.

I then created a directory (a git repo in the future, but not for now) where I'd be able to setup the config files for the worker, controller, and local machine. In k8s fashion, once the liveusb boots into talos all that I need to do to configure a node is apply a laboriously detailed config.

## Creating a config file

This is actually not as laborious as I feared, there are a few odd details not described in the docs but easily enough resolved with a bit of smart guessing work. I use `talosctl gen config` to create the `worker.yaml`, `controlplane.yaml`, and `talosconfig`; the first two going to the worker and controller respectively and the last providing the keys to be able to access the cluster. After flags, here's my command:

```bash
talosctl gen config \
    kclt-01 `# the name of the new cluster` \
    https://10.64.0.48:6443 `# the endpoint, in this case an unused IP to` \
       `# serve as the L2 shared IP` \
    --install-disk "/dev/nvme0n1" `# Self explanatory, all nodes will have an` \
    `# nvme0n1 so this is ok to use as a magic value.` \
    --additional-sans "$PUBLIC_IPV4" `# just the IP 1.2.3.4, no URI or port.` \
    --additional-sans "kclt-01.kube.api.dotfile.sh" `# for a cleaner way to` \
    `# access it if my public ipv4 has to change, DNS will be automatically` \
    `# handled by the cluster and pushed to cloudflare like how I do certs.` \
    --config-patch '[{"op":"add", "path": "/cluster/network/cni", "value": {"name": "none"}}]'
     # This disables the default CNI (flanel) or providing links to another CNI
     # manifest. I will be using Cilium which is best installed over helm.
```

> Note: *Technically* if I wanted I could include this next bit as `--config-patch`es in the main command, but this is easier all else equal.

This generates ~90% of what I needed, however there were still a few additional changes to be made, specifically enabling the VIP, enabling the use of ports < 1024, and commenting out some config. Below, I've listed what I've added:

```yaml
# controlplane.yaml
machine:
  network:
    interfaces:
      - interface: eth0
        mtu: 1500
        dhcp: true # either this OR a static IP MUST be set, otherwise the system will just freeze up as it has no idea what to do about networking.
        vip:
          ip:  10.64.0.48
  files:
    - content: |
        [plugins."io.containerd.grpc.v1.cri"]
            enable_unprivileged_ports = true
            enable_unprivileged_icmp = true
      path: /var/cri/conf.d/allow-unpriv-ports.toml
      op: create
```

```yaml
# worker.yaml
machine:
  network:
    interfaces:
      - interface: eth0
        mtu: 1500
        dhcp: true # either this OR a static IP MUST be set, otherwise the system will just freeze up as it has no idea what to do about networking.\
  files:
    - content: |
        [plugins."io.containerd.grpc.v1.cri"]
            enable_unprivileged_ports = true
            enable_unprivileged_icmp = true
      path: /var/cri/conf.d/allow-unpriv-ports.toml
      op: create
```

# Bootstrap Boobery

> **Note**: This is a glorified rant on a list of debugging I had to do to get an NVMe drive to boot on an old server, and doesn't really have any baring on the rest of my talos setup. [Skip to the next section](#installation) if you don't care.

Despite supposedly complying with UEFI v2.3, as it turns out 13th generation Dell PowerEdge servers, or at least the PowerEdge R630 I was planning as a worker, had some rather severe asterisks about booting off of NVMe drives. This was a rather unfortunate revelation. It had come after I had already ordered a volley of them to use as my nodes' boot drives and more relevantly that order was outside its return window (It was also not realized until well after I had actually installed everything, confusing the hell out of me resulting in a fun evening of plugging the Dell's NVMe into every other machine trying to debug the issue and searching for illusory OEM parts on eBay, but that's neither here nor there)

Faced between being out a whole $25 and buying a SATADOM or spending no less than a week trying to hack together a bad solution to a problem that could've been prevented with a bit of foresight, I chose the reasonable option and delayed this thing even further.

There were a few approaches available:

- Load NVMe support in software and make any further issues Talos's responsibility.
- Netboot talos from an external server
- Install talos to a USB, and use custom install parameters so the write parts of the disk are located on a mounted NVMe.

With these in mind, I outlined what I wanted my proper solution to be:

1. Generic enough to be used with an arbitrary number of disks/servers and work without additional modification for each one
2. Require minimal to no upkeep
3. Not introduce an external point of failure such as a remote server hosting ISOs
4. Take no arbitrary performance hit at runtime
5. Cost no more than ~$20 to fix for all machines I could have (six)

This narrowed the field significantly: 

- I couldn't buy some illusory OEM component or high end NVMe for each server as even secondhand that would be heaven knows how much. 
- I didn't want to setup netboot as if *that* server were to die all attempts to boot nodes would crash and burn, 
- Talos on a USB stick was my favorite candidate until I was told by a member of the Sidero team that I'd eat performance due to how Talos assumes full lifecycle of the install disk. 

My last hope then was to attempt to circumvent the entire issue by booting off media which my server *would* accept, load an NVMe driver, and hand off to Talos. When it comes to tricking backwards software into performing otherwise basic functionality, the Hackintosh community is always 10 steps ahead.

## Unlucky Clover

[Clover](https://github.com/CloverHackyColor/CloverBootloader) is a bootloader used mainly for tricking machines into thinking they're macintoshes. As such, it comes with a variety of EFI drivers to preload goodies which macOS generally has handed to it on a silver platter by the T2 security chip and iBoot (or whatever the ARM setup uses now-a-days).

> Note: In retrospect, this probably should've been done by me anyway, as I like to have a setup prepared for any scenario, and older hardware is something I feel I shouldn't neglect just because I lucked out in getting relatively recent kit.

After some research, the general gist that similar posts online had described was to copy the driver from `/EFI/CLOVER/drivers/off/NvmExpressDxe.efi` to `/EFI/CLOVER/drivers/UEFI/NvmExpressDxe.efi` and `/EFI/CLOVER/drivers/BIOS/NvmExpressDxe.efi`, add finally an entry to the `config.plist` which outlined the GUID of the partition to boot to. This, however, went against outline #1 that I had set out; I would have to edit the config for every new server and every new disk. So I spent another week banging my head against the docs and solved the problem.

### Resulting config

The clover documentation luckily provides an alternative way to select the boot disk. Rather than the GUID of the disk, you can [provide a disks label](https://github.com/CloverHackyColor/CloverBootloader/wiki/Configuration#defaultvolume) and it can boot off that.

Talos's EFI is just labeled [EFI](https://www.talos.dev/v1.1/learn-more/architecture/) and the executable is at `\EFI\BOOT\BOOTX64.efi`. As talos is just cloned uniformly from an ISO, on each machine there will be one `EFI:\EFI\BOOT\BOOTX64.efi` so it was general enough to be effectively read only.

> **Note**: If the talos team ever changes any of that, I'm so screwed. But I don't see at all why they would.

I'll show the changed config, but not the entire thing (which is ~1400 lines), I'll put a full version up on my Git however in case there's something I am missing:

> **TODO:** ADD A GIT LINK. IF YOU ARE READING THIS LONG AFTER PUBLICATION AND WANT THAT FILE PLEASE EMAIL ME USING THE LINK ON MY MAIN PAGE.

Menu option:

```xml
<key>Boot</key>
<dict>
  <!-- Other keys have been omitted for brevity -->
  <key>DefaultLoader</key>
  <string>EFI\BOOT\BOOTX64.efi</string>
  <key>DefaultVolume</key>
  <string>EFI</string>
  <key>Timeout</key>
  <integer>0</integer>
</dict>
```

Underlying boot option:

```xml
<key>GUI</key>
<dict>
  <key>Custom</key>
  <dict>
      <key>Entries</key>
      <array>
        <dict>
          <key>Hidden</key>
          <false/>
          <key>Volume</key>
          <string>EFI</string>
          <key>Disabled</key>
          <false/>
          <key>Type</key>
          <string>Linux</string>
          <key>Title</key>
          <string>TALOS</string>
        </dict>
      </array>
    <!-- Other keys have been omitted for brevity -->
  </dict>
  <!-- Other keys have been omitted for brevity -->
</dict>
```

> Note: Make sure these keys are not prefixed with a `#`, which the clover team does to comment out keys if they are not needed. This tripped me for an embarrassing sum of time.

With these two added, so long as that USB was set to be the default boot device for each server, it would start Grub without issue. My next step was to generalize.

### Making an `.img`

> **Sources**:
>
> I don't know really what I was doing, so here's the fine articles I glanced over to figure out:
>
> - [Ubuntuhak "how to create, format, and mount .img files"](https://ubuntuhak.blogspot.com/2012/10/how-to-create-format-and-mount-img-files.html)
> - [Jarret W. Buse "Create IMG Files"](https://www.linux.org/threads/create-img-files.11174/)

I wanted this setup to be easily cloned for each machine's boot USB. To achive this, I created a `.img` which would be burned onto each USB rather than manually making each partition, taking a mere hour to save precious seconds later.

I first created my .img by `dd`ing zeroes to a new `talos.img` file; this was not going to be a large thing so I decided 256MB would work:

```
sudo dd if=/dev/zero of=${SOMEPATH}/clover.img bs=64MB count=4
```

Then I setup the loop device and setup the partition:

```
sudo losetup /dev/loop0 ${SOMEPATH}/clover.img ; sudo fdisk ${SOMEPATH}/clover.img
```

I used fdisk to create a new `EFI System` partition, which I then mounted. I also mounted and copied the [clover ISO](https://github.com/CloverHackyColor/CloverBootloader/releases/) (making the edits above) as the .iso is a readonly affair.

Once done, I installed it and the thing works like a charm.

> **"Fixing" a failed installation**: A footer of a footer here; Chronologically, I tried the next step before this one but after fixing this issue, I wanted to make a couple changes to the install anyway. As Talos had already tried and failed to be installed before, if I wanted to boot off of a liveUSB to reinstall, the ISO would simply start up the existing install. To fix that I did the ugly thing of booting to a Debian liveUSB, `dd`ing some zeros to the disk, and installing talos that way.

# Installation

As I was not starting a CNI at installation, I had to do this in two steps. A single controller had to be initialized before any other machines added:

> **Note**: I was looking to assign each machine a special hostname, if only because I thought it would be cool. To do this though, I first had to make a copy of each nodes' respective controlplane/worker.yaml and set `machine.network.hostname`. apply-config doesn't have a [config patch](https://jsonpatch.com/) option like `--config-patch '[{ "op": "add", "path": "/machine/network/hostname", "value": "${VALUE}" }`

```sh
talosctl apply-config --insecure --nodes ${NODE_IPV4} --file=controlplane.yaml
```

## Setting up the client

After a while, it pulled all the images needed and rebooted into the newly installed system. I merged the generated `talosconfig` into my local machine's global talos config setup:

```bash
talosctl --talosconfig=./talosconfig \
  config endpoint 10.64.0.48 ${NODE_IPV4}
talosctl --talosconfig=./talosconfig \
   config node ${NODE_IPV4}
talosctl config merge ./talosconfig
```

> **Talos endpoints != k8s endpoints**: This either isn't made particularly clear in the documentation (or I am not particularly bright, it's a coin flip), but what your talos endpoint(s) are vs what your k8s endpoint is are not necessarily the same. I bring this up as it's why I am not simply using the `10.64.0.48` L2 shared IP, as that is dependent on a lot of things so if etcd fails you completely lose access to your cluster. The alternative was DNS, which is probably smarter, but my home network is already a mess so an internal DNS server wasn't a project I was jumping at the chance to work on.

## Starting k8s

This is great, this is the easy part.

```bash
talosctl bootstrap --nodes ${NODE_IPV4}
```

> This command is run once. Future nodes added to the cluster will simply use the `talosctl apply-config #{...}` command.

After a moment, it setup k8s and I could merge the kubeconfig for it into my local machine's global kubeconfig:

```
talosctl kubeconfig
```

Finally, before I could add other machines I had to install the CNI. I decided to use Cilium as Calico was a bit too hefty for my max 6 nodes without many benefits. I won't go into this but excellent documentation is available from the Sidero team themselves [here](https://www.talos.dev/v1.1/kubernetes-guides/network/deploying-cilium/). After this, I could add the remaining server~~s~~.

# Installing the Worker

I only had one other machine to add at the time, and adding additional nodes is a cinch.

```sh
talosctl apply-config --insecure --nodes ${NODE_IPV4} --file=worker.yaml
```

This pulled the necessary containers, installed to the disk, and started up.

# Next Steps

Now that the base cluster has been setup, I can outline the next few posts:

1. Install necessary services, mainly MetalLB, cert-manager, traefik, and rook/ceph.
2. Migrate data from B@Dv2 to the new cluster.
3. Add lailah and mastema to the cluster.
4. Replace B@Dv2 with v3 as my primary production cluster.
5. Add new apps, new services, etc. With that done, the sky is the limit.

# EOF