#!/bin/bash

# Project offsite_backup
# Copyright (C) 2022 Bernd Stroessenreuther <booboo@gluga.de>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#############################################################################
# this script creates an off-site backup
# by default exactly one backup generation is kept off-site
# (recommendation: have more generations available locally)
# the backup is encrypted with gocryptfs, see 
# https://nuetzlich.net/gocryptfs/quickstart/
#############################################################################

#############################################################################
# config section
#############################################################################

# local: spool directory for the crypted content
SPOOL_DIR_CRYPTED="/var/cache/offsite_backup/crypted"

# local: mountpoint for decrypted content of SPOOL_DIR_CRYPTED
SPOOL_DIR_CLEARTEXT="/var/cache/offsite_backup/cleartext"

# local: lockfile to avoid double start
LOCK_FILE="/var/lock/offsite_backup"

# remote: Hostname and username for the machine you want to
#         transfer the encrypted backup to
REMOTE_SERVER_HOSTNAME="storage-provider.example.com"
REMOTE_SERVER_USERNAME="storageuser"

# remote: directory where to store the encrypted backup
#         If the path starts with a slash "/" it is interpreted as an
#         absolute path.
#         Otherwise it is relative to the home directory of user
#         REMOTE_SERVER_USERNAME
REMOTE_SERVER_DIR="/opt/offsite_backup"

# special rsync options when syncing to the remote server
# e. g. use max 0.7 MB/sec of bandwidth, when rsyncing to the remote server
# REMOTE_SERVER_RSYNC_OPTIONS="--bwlimit=0.7m"
REMOTE_SERVER_RSYNC_OPTIONS=""

# special ssh options when accessing the remote server
# e. g.
# REMOTE_SERVER_SSH_OPTIONS="-i /root/.ssh/id_ed25519.offsite_backup"
REMOTE_SERVER_SSH_OPTIONS=""

#############################################################################
# config section: end
#############################################################################

#
# avoid possible double start of this script
#

if [[ ! -e $LOCK_FILE ]]; then
    echo $$ > $LOCK_FILE
else
    pgrep --pidfile $LOCK_FILE >/dev/null
    PGREP_RC=$?
    if [[ PGREP_RC -eq 0 ]]; then
        echo another instance of offsite_backup.sh is already running
        exit 1
    else
        echo removing old lock file:
        ls -l $LOCK_FILE
        echo with content:
        cat $LOCK_FILE
        rm $LOCK_FILE
        echo $$ > $LOCK_FILE
    fi
fi

# .-- functions --------------------------------------------------------------
help () {
    cat << EOF

call using:

$0
    to start an offsite backup

$0 -l
    update local copy only
    (do not sync it to remote)

$0 -r
    sync local copy to the remote location only
    (but do not update the local copy)

$0 -i
    to initialize the gocryptfs in $SPOOL_DIR_CRYPTED

$0 -m
    to mount the gocryptfs to $SPOOL_DIR_CLEARTEXT

$0 -u
    to umount the gocryptfs

$0 -R
    Restore:
    sync the encrypted copy from the remote server
    (${REMOTE_SERVER_HOSTNAME})
    back to the local directory
    ${SPOOL_DIR_CRYPTED}
    Please note: The gocryptfs may not be mounted for restore.
    (will try umount if needed)

EOF
}

leave () {
    rm $LOCK_FILE
    exit "$1"
}

leave_with_umount () {
    umount_gocryptfs
    rm $LOCK_FILE
    exit "$1"
}

report_and_exit () {
        REPORT_STATUS=$1
        REPORT_MESSAGE=$2

    case $REPORT_STATUS in
        0) STATUS_DESCRIPTION="OK" ;;
        1) STATUS_DESCRIPTION="WARNING" ;;
        2) STATUS_DESCRIPTION="CRITICAL" ;;
        3) STATUS_DESCRIPTION="UNKNONW" ;;
    esac

    # here you can report the status of the job to your favourite
    # monitoring system, e. g.
    # MESSAGE="$MY_HOSTNAME;offsite_backup;$REPORT_STATUS;$STATUS_DESCRIPTION - $REPORT_MESSAGE"
    # echo $MESSAGE | send_by_nsca
    echo "$STATUS_DESCRIPTION: $REPORT_MESSAGE"

    leave "$REPORT_STATUS"
}

update_max_rsync_rc_if_needed () {
    CURRENT_RC=$1

    echo -e "${LIGHT_BLUE}###${NO_COLOR} rsync ${LIGHT_CYAN}return code: ${CURRENT_RC}${NO_COLOR}"
    if [[ $CURRENT_RC -gt $MAX_RSYNC_RC ]]; then
        MAX_RSYNC_RC=$CURRENT_RC
    fi
}

ensure_dir () {
    DIR_PATH=$1

    if [[ ! -d "$DIR_PATH" ]]; then
        mkdir -p "$DIR_PATH" && chmod 700 "$DIR_PATH"
    fi
}

init_gocryptfs () {
    ensure_dir $SPOOL_DIR_CRYPTED
    gocryptfs -init $SPOOL_DIR_CRYPTED
}

mount_gocryptfs () {
    ensure_dir $SPOOL_DIR_CRYPTED
    ensure_dir $SPOOL_DIR_CLEARTEXT

    echo
    echo -e "${LIGHT_BLUE}### mounting spool dir${NO_COLOR}"
    echo -e "${LIGHT_BLUE}###${NO_COLOR} (${LIGHT_CYAN}${SPOOL_DIR_CRYPTED}${NO_COLOR} to ${LIGHT_CYAN}$SPOOL_DIR_CLEARTEXT${NO_COLOR})"
    if [[ $(mount | grep -c -E "^${SPOOL_DIR_CRYPTED} on ${SPOOL_DIR_CLEARTEXT} type fuse.gocryptfs") -gt 0 ]]; then
        echo -e "${ORANGE}Already mounted${NO_COLOR}"
    else
        gocryptfs $SPOOL_DIR_CRYPTED $SPOOL_DIR_CLEARTEXT || leave 1
    fi
}

umount_gocryptfs () {
    echo
    echo -e "${LIGHT_BLUE}### checking if gocryptfs ${SPOOL_DIR_CRYPTED} is mounted${NO_COLOR}"
    MOUNT_COUNT=$(mount | grep -c -e "^${SPOOL_DIR_CRYPTED} ")

    if [[ $MOUNT_COUNT -eq 0 ]]; then
        echo "No, not mounted"
    else
        echo
        echo -e "${LIGHT_BLUE}### umounting spool dir${NO_COLOR}"
        fusermount -u $SPOOL_DIR_CLEARTEXT || leave 1
    fi
}

restore () {
    ensure_dir $SPOOL_DIR_CRYPTED
    ensure_dir $SPOOL_DIR_CLEARTEXT

    echo
    echo -e "${LIGHT_BLUE}### Restore: syncing back crypted content from remote server (${REMOTE_SERVER_HOSTNAME}) to ${SPOOL_DIR_CRYPTED}${NO_COLOR}"
    # need to create a command like
    # rsync -avP --delete --delete-before -e "ssh -i /root/.ssh/id_ed25519.offsite_backup" storageuser@storage-provider.example.com:/opt/offsite_backup/crypted/* /var/cache/offsite_backup/crypted
    BASENAME_SPOOL_DIR_CRYPTED=$(basename $SPOOL_DIR_CRYPTED)
    # shellcheck disable=SC2086
    rsync -avP ${REMOTE_SERVER_RSYNC_OPTIONS} --delete --delete-before -e "ssh ${REMOTE_SERVER_SSH_OPTIONS}" ${REMOTE_SERVER_USERNAME}@${REMOTE_SERVER_HOSTNAME}:${REMOTE_SERVER_DIR}/${BASENAME_SPOOL_DIR_CRYPTED}/* ${SPOOL_DIR_CRYPTED}
    update_max_rsync_rc_if_needed $?

    leave "$MAX_RSYNC_RC"
}

set_colors () {
    # default: no colors
    ORANGE=''
    LIGHT_BLUE=''
    LIGHT_PURPLE=''
    LIGHT_CYAN=''
    NO_COLOR=''

    # first of all: test if we are in a terminal
    if [[ -t 1 ]]; then

        # see if it supports colors...
        ncolors=$(tput colors 2>/dev/null)

        if [[ -n "$ncolors" ]] && [[ $ncolors -ge 8 ]]; then
                  ORANGE='\033[0;33m'
              LIGHT_BLUE='\033[1;34m'
            LIGHT_PURPLE='\033[1;35m'
              LIGHT_CYAN='\033[1;36m'

                NO_COLOR='\033[0m' # No Color
        fi
    fi

    # use:
    # echo -e "${ORANGE}test${NO_COLOR}"
}
#.

# .-- defining variables -----------------------------------------------------

MAX_RSYNC_RC=-1
UPDATE_LOCAL_COPY=1
UPDATE_REMOTE_COPY=1

#.

set_colors

# .-- commandline parameters -------------------------------------------------
while getopts iumRrlh opt
do
    case $opt in
        i)
            init_gocryptfs
            leave 0
            ;;
        u)
            umount_gocryptfs
            leave 0
            ;;
        m)
            mount_gocryptfs
            leave 0
            ;;
        R)
            umount_gocryptfs
            restore
            leave 0
            ;;
        r)
            UPDATE_LOCAL_COPY=0
            ;;
        l)
            UPDATE_REMOTE_COPY=0
            ;;
        h)
            help
            leave 0
            ;;
        *) echo "unknow option: $1"
            help
            leave 1
            ;;
    esac
done
#.

#
# create the backup
#

if [[ $UPDATE_LOCAL_COPY -eq 1 ]]; then

    mount_gocryptfs

    #########################################################################
    # DO CHANGES HERE
    #
    # You are especially expected to do changes in this section:
    #    * Make sure you change the rsync jobs below according your needs
    #    * Add additional rsync jobs where needed to sync your relevant
    #      data into the local spool directory
    #    * Take care about --exclude parameters to make sure you exclude
    #      unnecessary stuff to keep a reasonable size
    #########################################################################

    ### /home
    echo
    echo -e "${LIGHT_BLUE}### updating content of spool dir: ${LIGHT_PURPLE}/home${NO_COLOR}"
    # for exclude statements see https://unix.stackexchange.com/questions/83394/rsync-exclude-directory-not-working
    rsync -avP --no-devices --no-specials --delete --delete-before --delete-excluded --exclude="/home/*/.cache/***" --exclude="/home/*/tmp/***" --exclude="/home/*/.mediathek3/***" /home ${SPOOL_DIR_CLEARTEXT}
    update_max_rsync_rc_if_needed $?

    ### /root
    echo
    echo -e "${LIGHT_BLUE}### updating content of spool dir: ${LIGHT_PURPLE}/root${NO_COLOR}"
    rsync -avP --no-devices --no-specials --delete --delete-before --delete-excluded --exclude="/root/tmp/***" /root ${SPOOL_DIR_CLEARTEXT}
    update_max_rsync_rc_if_needed $?

    ### /etc
    echo
    echo -e "${LIGHT_BLUE}### updating content of spool dir: ${LIGHT_PURPLE}/etc${NO_COLOR}"
    rsync -avP --no-devices --no-specials --delete --delete-before --delete-excluded /etc ${SPOOL_DIR_CLEARTEXT}
    update_max_rsync_rc_if_needed $?

    ### /usr/local
    echo
    echo -e "${LIGHT_BLUE}### updating content of spool dir: ${LIGHT_PURPLE}/usr/local${NO_COLOR}"
    [[ -d ${SPOOL_DIR_CLEARTEXT}/usr ]] || mkdir -p ${SPOOL_DIR_CLEARTEXT}/usr || leave_with_umount 1
    rsync -avP --no-devices --no-specials --delete --delete-before --delete-excluded --exclude="/local/src/***" /usr/local ${SPOOL_DIR_CLEARTEXT}/usr
    update_max_rsync_rc_if_needed $?

    umount_gocryptfs

fi

if [[ $UPDATE_REMOTE_COPY -eq 1 ]]; then

    echo
    echo -e "${LIGHT_BLUE}### syncing crypted content to remote server (${REMOTE_SERVER_HOSTNAME})${NO_COLOR}"
    # need to create a command like
    # rsync -avP -e "ssh -i /root/.ssh/id_ed25519.offsite_backup" /var/cache/offsite_backup/crypted storageuser@storage-provider.example.com:/opt/offsite_backup
    # shellcheck disable=SC2086
    rsync -avP ${REMOTE_SERVER_RSYNC_OPTIONS} --delete --delete-before -e "ssh ${REMOTE_SERVER_SSH_OPTIONS}" ${SPOOL_DIR_CRYPTED} ${REMOTE_SERVER_USERNAME}@${REMOTE_SERVER_HOSTNAME}:${REMOTE_SERVER_DIR}
    update_max_rsync_rc_if_needed $?

    echo
    echo -e "${LIGHT_BLUE}### making sure local and remote are in sync${NO_COLOR}"
    # shellcheck disable=SC2086
    rsync -avP ${REMOTE_SERVER_RSYNC_OPTIONS} --delete --delete-before -e "ssh ${REMOTE_SERVER_SSH_OPTIONS}" ${SPOOL_DIR_CRYPTED} ${REMOTE_SERVER_USERNAME}@${REMOTE_SERVER_HOSTNAME}:${REMOTE_SERVER_DIR}
    update_max_rsync_rc_if_needed $?

fi

if [[ $UPDATE_REMOTE_COPY -eq 1 ]] && [[ $UPDATE_LOCAL_COPY -eq 1 ]]; then
    echo
    echo -e "${LIGHT_BLUE}### Reporting${NO_COLOR}"
    if [[ ${MAX_RSYNC_RC} -eq 0 ]]; then
        report_and_exit 0 "no problems have been reported during offsite_backup"
    else
        report_and_exit 1 "at least one rsync ended with a non-zero return code (RC=${MAX_RSYNC_RC})"
    fi
else
    echo
    echo -e "${LIGHT_BLUE}### NO Reporting${NO_COLOR}"
    echo "This was not a full backup but a limited update with -l or -r only"
    leave 0
fi
