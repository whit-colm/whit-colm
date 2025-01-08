#!/bin/bash

# explicit PATH, and umask
export PATH=/usr/bin:/bin/:/usr/sbin:/sbin:/usr/local/bin:/usr/lib/go-1.23/bin
mkdir -p /tmp/whits.io-updates/
umask 0077

# Start logging things, put both STDERR and STDOUT into said log.
ME=$(basename "${0}")
exec 3>&2 >> /tmp/whits.io-updates/"${ME}"-$(date +%s).log 2>&1
# sets:
# - errexit: exit if simple command fails (nonzero return value)
# - nounset: write message to stderr if trying to expand unset variable
# - verbose: Write input to standard error as it is read.
# - xtrace : Write to stderr trace for each command after expansion.
set -euvx
uname -a
date

bang () { echo FAILED. >&3; exit 1; } 
trap bang EXIT

###############################################################################
###    This script is a not-particularly-elegant way of syncing changes.    ###
###############################################################################
# -  Every 30 minutes this command will run on the server which is hosting the
#    website.
#
# 1. Check the most recent commit hash of the repo
# 2. If the most recent hash == ./whitsio.hash then the program exits and waits
#    to be triggered again.
# 3. If the most recent hash != ./whitsio.hash, then ./whitsio.hash is deleted
#    and the repo is pulled to the latest commit in main.
# 4. Hugo is called to compile the website into .../public/
# 5. The data of /var/www/whits.io/public/* is deleted
# 6. Ownership of .../public is changed to www-data:www-data
# 7. The contents of .../public/ is moved into /var/www/whits.io/public/
# 8. The new most recent hash is stored in ./whitsio.hash, and the process 
#    repeats.

readonly Remote_Reop_Url='https://github.com/whit-colm/whitsio'
readonly Repo_Branch='main'
readonly Repo_Dir="${HOME}/whitsio"
readonly Hash_File="${HOME}/whitsio.hash"

readonly Headhash=$(git ls-remote "${Remote_Reop_Url}" "${Repo_Branch}")
readonly Lasthash=$(cat "${Hash_File}" || echo "nofile" )

if [ "${Headhash}" = "${Lasthash}" ]; then
    trap - EXIT
    exit 0
fi

# If we're here, that means there is a new site to make. 
# We delete ./witsio.hash; if it doesn't exist that's fine too. we "or no-op"
rm "${HOME}"/whitsio.hash || :

# We pull forward the $HOME/whitsio dir if it does exit, or do a clone if it
# does not.
if [ -d "${Repo_Dir}" ]; then
    cd "${Repo_Dir}"
    git fetch --depth 1 origin "${Repo_Branch}"
    git reset --hard FETCH_HEAD
    git reflog expire --expire=now --all
    git gc --prune=now
    cd -
else
    echo "Repo does not exist at ${Repo_Dir}, cloning."
    git clone --depth 1 --branch "${Repo_Branch}" "${Remote_Reop_Url}" "${Repo_Dir}"
fi

# Generate the website with hugo and set correct ownership
cd "${Repo_Dir}"
hugo
chown -R www-data:www-data ./public/*

# Since the website has to be deleted, we need to make sure *something* stays up
# if there is an error. If something goes wrong, this traps the error and 
# copies a known safe website into the nginx folder and does some truly awful
# regex to boot.
errSite () {
    readonly Current_Date_Time=$(date "+%F %T %Z")
    cp -r "${HOME}"/safesite /var/www/whits.io/public/
    perl -pe "s/%UPDATETIME%/${Current_Date_Time}/g" -i \
        /var/www/whits.io/public/index.html
    bang
}
trap errSite EXIT

# remove the existing contents of the nginx site
rm -rf /var/www/whits.io/public/*
mv ./public/* /var/www/whits.io/public/

# We still have a few operations, but we are done writing to
# /var/www/whits.io/public
trap bang EXIT

# We are done! we can copy the new hash into whitsio.hash and exit.
echo "${Headhash}" > "${Hash_File}"

trap - EXIT
exit 0