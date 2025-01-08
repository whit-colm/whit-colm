+++
date = 1736141688
draft = false
showReadingTime = true
title = 'Bringing Back `whits.io`'
summary = "After far too many years offline due to self-impose infrastructure obstacles, It's time to actually start using my website again."
description = "Notes on relaunching my website"
tags = ["relevant"]
+++

Dollar short and a day (or 1,461) late, but I'm finally bringing my old website back online. I've never really been one for front-end webstuff, but I *am* very fond of rambling so I've been itching to get it working again. It's just a [hugo](https://gohugo.io) static site ([congo theme](https://jpanther.github.io/congo/)) with my patent migraine backend infrastructure behind it.

There's not much to add; for the past few years my website has just 302'd to my GitHub profile, but now runs on a (admittedly tiny) DigitalOcean Droplet running Nginx backed by Certbot-LetsEncrypt. Kinda an anachronism now, certainly reminiscent of what I was doing a decade ago. I did not want any credentials stored, and because the website's repo is public site updates happen according to a droplet cron job. It's not modern and event-triggered like it probably should be, but it's simple, safe, and it works, which is all that matters in the end.

The cron job runs a shell script which does the following:

1. Check the most recent commit hash of the repo
2. If the most recent hash is equivalent to the last checked hash (stored in `./main.hash`) then the program exits and waits to be triggered again.
3. If the most recent hash is different from ./main.hash, then `./main.hash` is deleted and the repo is pulled to the latest commit in branch main.
4. `hugo` is called to compile the website into `.../public/`
5. The data of `/var/www/whits.io/public/*` is deleted
6. Ownership of `.../public` is changed to `www-data:www-data`
7. The contents of `.../public/` is moved into `/var/www/whits.io/public/`
8. The new most recent hash is stored in `./main.hash`, and the process repeats.

The script used is available [on the site's GitHub repo](https://github.com/whit-colm/whitsio/blob/main/refresh.sh)

It is worth noting that due to how old Debian is, Go had to be installed via backports and Hugo from the `.deb` from their GitHub releases page.

---

Yes this could just be a GitHub Pages website, but where's the fun in that? (real reason: I forgot that existed before I was in too deep)