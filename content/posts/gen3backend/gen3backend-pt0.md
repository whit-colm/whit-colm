---
title: "[Backend@Dotfile v3] Part 0 - 'Episode III: Also Sprach Zarathustra'"
date: 2022-06-26T08:57:37-05:00
description: "Recipe for pretzel bites"
summary: " "
draft: false
tags: ["bdv3", "Kubernetes"]
---

# The Eternal Cycle

An interesting fact is that my adventures in using a homebrewed, hacked-together Kubernetes cluster (Backend@Dotfile v2) were never published. It served me for more than a year, but I could never get a lot of the big kinks ironed out, and many services I used from B@Dv1 (ServerStack) didn't scale well from a single node Docker Swarm onto HA Kubernetes. This meant I could never get the git stuff setup properly enough to publish my website so it's been down for a year or so. If you are reading this, well that's good.

Fixing these issues would have required a horrific amount of effort to fix while maintaining an architecture I was not particularly fond of; the necessary improvements on top of that would not have been fathomable. With more physical servers at my disposal, I decided to scrap the whole thing and design from scratch, using what I learned to make something which would better support me going forward.

# The Plan

One of the most important things in realizing what this improved design looked like was to realize what, in its entirety, the platform was going to run on. By realizing I was not AWS, I could instead focus on the countable, finite amount of servers I could possibly have and design my solution around that. Using my own light sensitive electrochemical visualization system, then using complex arithmetic algorithms to finally store the result on highly versatile calculatory appendages (i.e. using my eyes to look at my server rack and counting on my fingers) I was able to derive a definitive answer:

Six servers.

My rack, fit very appealingly in a corner of my living room, has room for a rack mounted router+switch, power equipment, and 6 servers. With this number in mind, I realized many of my concerns were irrelevant. I still wanted the system to be able to be implemented on as little as a single node, but I wouldn't have to consider applying the tech to a multi-row datacenter.

## Software

One of the epiphanies I had in the latter work on B@Dv2 was that virtual machines helped nothing, and in fact required significant constraints to run. Very rarely would VMs fail on their own without the host server going down as well. Using VMs also required some finessing of server RAID so any disk failure wouldn't destroy data, which was shown to be woefully inefficient. Finally, the cluster sat on top of this house of cards and would frequently drop dead if the HAProxy machines disagreed, which they almost always did (never figured out that bug).

With this in mind, I wanted to centralize as much as I could and cut unnecessary and non-functional redundancy where possible. The heart of the answer (as first recommended to me by my good friend and mentor [Mr. Rob](https://rwx.gg) was [Talos Linux](https://talos.dev).

- Talos Linux
  - Talos is a stripped down, API driven Linux distro meant to do one thing: create an environment for k8s. There is no shell, no user access, no console. It connects to the internet, starts the kubernetes toolchain, and shuts up.
  - Through utilizing Talos, I can minimize any issues relating to the OS and perform administration via the kubernetes API through CRDs.
  - Talos provides builtin L2 IP sharing, which is extremely helpful and removes the need of an entirely discrete system to manage high availability.
- Rook-Ceph
  - Storage cluster which organizes and stripes multiple disks across multiple nodes, provides a single endpoint for multiple types of storage (block, file, object)
    - This removes the need for each node to perform its own RAID, and *should* allow me to arbitrarily add disks as I get the money for them, without horribly throttling IO for the server to rebuild the RAID.
      - All components within ceph are cluster-aware, data storage is determined via an algorithm called CRUSH rather than a single source of truth.
  - While more complex than v2's Longhorn, through a few enhancements in hardware this complexity and monolithic nature works in my favor, without the layer cake of relatively more simple storage systems which v2 required.
    - For reference, something like object storage on v2 was comprised of a mess:
      1. Hardware RAID merged multiple physical disks into a single device
      2. Hosts ran on hw RAID, and broke the single device into multiple logical volumes for VMs
      3. worker node VMs ran longhorn
      4. Longhorn provided disk redundancy, but due to the limited number of servers always stored the redundant data on nodes which shared a server.
      5. Object storage took out a PVC on longhorn
      6. Services accessed the object storage provider
    - V3's design is far less intimidating:
      1. Talos on each node provides rook-ceph access to the front panel disks
      2. Rook-ceph take complete control over these disks
      3. Rook-ceph clients expose this to other k8s objects as storage drivers
- CockroachDB
  - CockroachDB is an extreme high-performance SQL database intended for cloud environments such as k8s, and is intended provide a single database for which all apps talk to.
  - This is the one I am easily the least confident in, as it has shown not to play too stunningly with many apps in the past, and I fully expect to find a better solution which can speak vanilla PostgreSQL.

There are a few additional modifications, mainly replacing NextCloud with the new ownCloud Infinite Scale for native horizontal scaling, but that is for another time.

## Hardware

With a year of time to acquire new equipment, my rack is much more able to handle anything I throw at it:


| Slots | Item | Desc |
|:--:|:--|:--|
| 12 | Ubiquiti UDM-Pro | My previous router solution using OPNSense gave me consistant issues, if I knew a lick about networking outside of the bare minimum I could have probably fixed it but I honestly didn't think it was worth the effort, not to mention that I live with other people who quite enjoy having internet at home. This just kinda works and that's all I need as k8s does its own networking stuff |
| 11 | Ubiquiti USP-Pro | This cost too much and isn't relevant to anything, but I want to list what in all is in my rack |
| 10 | HP DL360g9 - "*Formula*" | Slots 9 and 10 will serve as the control planes of the cluster. |
| 9 | ??? - "*Urban*" | The second control plane, I have not bought it yet (I'm thinking a PowerEdge R430 though) but once I do I have seen that adding additional control planes is trivial with talos |
| 8 | Lenovo ThinkServer RD350 - "*Lailah*" | One of the holdovers from B@D v2, this will stay running that until I am confident in the new system's stability. While it currently uses some weird RAID system, the disks will be moved around once it is put onto the new Cluster. I shulked some 8TB SATA disks from Costco a while back and as these have 3.5" drive bays, I mean to add those to this. |
| 7 | Dell PowerEdge R630 - "*Verus*" | The other of my new servers. |
| 6, 5 | Dell PowerEdge R530 - "*Mastema*" | The second node on v2, this is easily the weakest machine and should probably have more memory and better processors slotted in given the power that it uses.
| 4, 3 | ??? - "*Amdusias II*" | I also have not bought this one yet. At the beginning of the year, I had to say goodbye to the original Amdusias as it was showing its 12 years of service. I plan to replace it with the best I can afford and will likely include a GPU for video encode/decode and *maybe* AI work if I wanna dip my toes in. |
| 2, 1 | TRIPPLITE SMART1500CRMXL | A UPS I got for concerningly cheap on Newegg several years ago, hasn't failed yet and I'm too afraid to go poking around and seeing about a battery change |

In addition to the front panel disks, all nodes have an NVMe drive which provides the persistence needed for etc.d by Talos, this is what allows me to dedicate all `sd*` drives to rook-ceph

# Next Steps

While this is a shorter than normal post, the next steps are more than just theorizing. So in the next post I'll go over initialization of the cluster.