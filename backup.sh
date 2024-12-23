#!/bin/bash
# Back up the /home directory to another directory.
# One argument is required on the command line, the name of
# the target directory where the backup is to be written to.
# The home directory will be copied (synced) to this directory.
# A full backup is done once per quarter and incremental backups
# thereafter.
#
# Since the backup directory is named with the date and not also the
# time, if this script runs more than once in the same day, a new
# backup directory will not be created, rather, the existing
# directory will be synced.
#
# Must be run with sudo.
#
# Jack Christensen 01Apr2016
# Enhanced to do incremental backups Jan 2019.

usage()
{
    PROGNAME=$(basename $0)
    echo "$PROGNAME usage: sudo $PROGNAME <destination-device>" >&2
    return
}

# ensure we're root (sudo)
ROOT_UID=0
if [[ $UID != $ROOT_UID ]]; then
    echo "This script must be run with sudo."
    usage
    exit 1
# ensure we have one command line argument
elif [[ $# -ne 1 ]]; then
    echo "Expecting one command line argument."
    usage
    exit 2
else
    SRC="/home"
    BACKUP_DIR="backup"
    OPTS='-ah --delete --info=progress2,stats'
    OPTS="$OPTS --exclude=/home/*/.cache/ --exclude=/home/*/.thumbnails/"

    # remove trailing slash from command line argument if present
    quarterPath=${1%/}

    # calculate path names
    m=$(date +%m)   # month
    m=${m#0}        # remove leading zero if present (prevent interpretation as octal)
    qtr=$(( ($m - 1) / 3 + 1 ))
    quarterPath="$quarterPath/$BACKUP_DIR/$(uname -n)/$(date +%Y)q$qtr"
    today=$(date +%F)
    backupPath="$quarterPath/$today"

    # create the quarterly directory if needed
    # creating it here rather than later ensures the ls command
    # doesn't fail when looking for the previous backup.
    mkdir -p $quarterPath
    mkStat=$?
    if [[ "$mkStat" != 0 ]]; then
        echo "Error $mkStat: Could not create directory $quarterPath"
        exit 3
    fi

    # find the previous backup subdirectory (most recent)
    prevBackup=$(ls -c --classify $quarterPath | egrep '.*/$' | sed -n '1p')
    if [ -n "$prevBackup" ]; then
        prevBackup=$quarterPath/${prevBackup::-1}
    fi
    # we assume only one backup per day. if more than one run is made on
    # the same day, then we will overwrite the destination from the previous run. 
    # this will cause the calculated backup directory name to be the same as
    # the previous backup, in which case we need to use the second most recent
    # as the prevBackup (link-dest).
    if [ "$backupPath" == "$prevBackup" ]; then
        prevBackup=$(ls -c --classify $quarterPath | egrep '.*/$' | sed -n '2p')
        if [ -n "$prevBackup" ]; then
            prevBackup=$quarterPath/${prevBackup::-1}
        fi
    fi
    # if we have a previous backup, use it as the link-dest directory,
    # and also have rsync write to the log file.
    logFile="$quarterPath/$today.log"
    if [ -n "$prevBackup" ]; then
        OPTS="$OPTS --link-dest=$prevBackup"
        OPTS="$OPTS --log-file=$logFile"
    else
        # the log-file-format option with empty format string causes
        # updated files to not be mentioned in the log. else the log
        # would be huge for a full backup.
        OPTS="$OPTS --log-file=$logFile --log-file-format="
    fi

    # create the backup directory if needed
    mkdir -p $backupPath
    mkStat=$?
    if [[ "$mkStat" != 0 ]]; then
        echo "Error $mkStat: Could not create directory $backupPath"
        exit 4
    fi

    # summarize paths & backup type
    echo -e "\nBacking up to:   $backupPath" | tee -a $logFile
    echo "Log file is:     $logFile" | tee -a $logFile
    if [ -n "$prevBackup" ]; then
        echo "Previous backup: $prevBackup" | tee -a $logFile
        echo "This is an incremental backup." | tee -a $logFile
    else
        echo "No previous backup found, this is a full backup." | tee -a $logFile
        echo "Limited rsync logging for full backup." | tee -a $logFile
    fi

    # proceed with backup, after user approves
    read -p $'\nProceed? [Y/n] '
    r=${REPLY,,}    # make lower case
    if [[ "$r" =~ ^[[:space:]]*n ]]; then
        echo "Backup aborted."
        exit 5
    else
        echo -e "\n$ rsync $OPTS $SRC $backupPath\n" | tee -a $logFile
        startTime=$(date +%s)
        echo "Backup starting at $(date --date=@$startTime "+%F %T")" | tee -a $logFile
        rsync $OPTS $SRC $backupPath
        echo "Wait for sync..." | tee -a $logFile
        sync
        endTime=$(date +%s)
        lapse=$(($endTime - $startTime))
        echo "Backup finished at $(date --date=@$endTime "+%F %T") Lapse $(date -u --date=@$lapse "+%H:%M:%S")" | tee -a $logFile
        echo -e "--------------------------------\n" >>$logFile
    fi
fi
