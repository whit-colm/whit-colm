#!/bin/bash

# explicit PATH, and umask
export PATH=/usr/bin:/bin/:/usr/sbin:/sbin
umask 0077

# Start logging things, put both STDERR and STDOUT into said log.
ME=$(basename "${0}")
ABS_DIR=$(dirname "$(realpath "${0}")")
exec 3>&2 >> "${ABS_DIR}"/"${ME}"-$(date +%s).log.nocommit 2>&1
# sets:
# - errexit: exit if simple command fails (nonzero return value)
# - nounset: write message to stderr if trying to expand unset variable
# - verbose: Write input to standard error as it is read.
# - xtrace : Write to stderr trace for each command after expansion.
set -euvx
uname -a
date

###############################################################################
###    This script is a not-particularly-elegant way of syncing changes.    ###
###############################################################################
# -  Every 30 minutes this command will run on the server which is hosting the
#    website.
#
# 1. Check the most recent commit hash of the repo
# 2. If the most recent hash == ./main.hash then the program exits and waits to
#    be triggered again.
# 3. If the most recent hash != ./main.hash, then ./main.hash is deleted and
#    the repo is pulled to the latest commit in main.
# 4. Hugo is called to compile the website into .../public/
# 5. The data of /var/www/whits.io/public/* is deleted
# 6. Ownership of .../public is changed to www-data:www-data
# 7. The contents of .../public/ is moved into /var/www/whits.io/public/
# 8. The new most recent hash is stored in ./main.hash, and the process repeats.
# 9. Clean-up steps

