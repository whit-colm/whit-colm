+++
date = 1736141688
lastmod = 1746635305
draft = false
showReadingTime = true
title = 'Bringing Back `whits.io`'
summary = "After far too many years offline due to self-impose infrastructure obstacles, It's time to actually start using my website again."
description = "Notes on relaunching my website"
tags = ["relevant"]
+++

{{< alert >}}
There's a serious issue in Hugo v0.146 and how it has reworked a lot of the shortcodes that makes building sites impossible with congo (and many other themes). [congo issue](https://github.com/jpanther/congo/issues/1049), [blowfish PR](https://github.com/nunocoracao/blowfish/pull/2055).
{{</ alert >}}


Dollar short and a day (or 1,461) late, but I'm finally bringing my old website back online. I've never really been one for front-end webstuff, but I *am* very fond of rambling so I've been itching to get it working again. It's just a [hugo](https://gohugo.io) static site (~~[congo](https://jpanther.github.io/congo/)~~ [*blowfish* theme](https://blowfish.page)). This was originally a bit of a thoughtless rush job wherein I spun up a DigitalOcean droplet and did some cron monstrosity to auto-build the site, mainly doing this so that I could also provide some larger files/files which I did not want to commit to this repo. Instead I've separated the two into a `files.whits.io` (the Droplet where I can rsync files to) and the site itself which now GitHub pages (like I should have done in the first place).

With my final semester at UNCC drawing to a close as of this edit, I hope I'll actually have time to commit to personal projects (and their write-ups). I look forward to being able to actually do something here!

{{< details summary="*Previous version of this blog post*" >}}

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

The script used is available [on the site's GitHub repo](https://github.com/whit-colm/whit-colm/blob/main/refresh.sh)

It is worth noting that due to how old Debian is, Go had to be installed via backports and Hugo from the `.deb` from their GitHub releases page (specifically the extended version for webp support).

{{</ details >}}

---

Yes this could just be a GitHub Pages website, but where's the fun in that? (real reason: I forgot that existed before I was in too deep)