#!/bin/bash
# Back up the /home directory to another hard disk using rsync.
# One argument is required on the command line, the device name
# of the hard disk where the backup is to be written to.
# The mount point for the destination disk is assumed to be
# /media/$USER/device-name where device-name is the name given on
# the command line. The home directory will be copied (synced)
# to /media/$USER/device-name/backup/hostname/yyyy-mm-dd.
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
#
# To do:
# Allow one or two command line arguments.
# Backup the /home directory from the local host a disk on the local host:
#   incr.sh <destination-device>
# Backup the /home directory from a remote host to a disk on the local host:
#   incr.sh <destination-device> <remote-hostname>
#   incr.sh <remote-hostname> <destination-device>
#
# Note for future enhancement, to back up the RPi over the network:
# rsync -a --delete --delete-excluded --info=progress2,stats --rsh=ssh pi@rpi:/home/pi /media/jack/data
# owner and group are not preserved but are changed to the current user on the
# receiving system, even if run with sudo. See the rsync --owner and --group options.

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
    exit 1
else
    SRC="/home"
    OPTS='-ah --delete --info=progress2,stats'
    OPTS="$OPTS --exclude=/home/*/.cache/ --exclude=/home/*/.thumbnails/"
    BACKUP_DIR="backup"
    DEVICE=$1
    USER_NAME=${SUDO_USER:-$USER}

    # test whether the given device is available
    devicePath="/media/$USER_NAME/$DEVICE"
    if [ -d "$devicePath" ]; then
        echo "Backing up to device: $devicePath"
    else
        echo "Error: Cannot find device: $devicePath"
        exit 2
    fi

    # test whether the backup directory is available
    backupPath="$devicePath/$BACKUP_DIR"
    if [ -d "$backupPath" ]; then
        echo "Directory exists: $backupPath"
    else
        echo "Creating directory: $backupPath"
        mkdir $backupPath
        mkStat=$?
        if [[ "$mkStat" != 0 ]]; then
            echo "Error $mkStat: Could not create directory $backupPath"
            exit 2
        fi
    fi

    # test whether the hostname directory is available
    hostPath="$backupPath/$(uname -n)"
    if [ -d "$hostPath" ]; then
        echo "Directory exists: $hostPath"
    else
        echo "Creating directory: $hostPath"
        mkdir $hostPath
        mkStat=$?
        if [[ "$mkStat" != 0 ]]; then
            echo "Error $mkStat: Could not create directory $hostPath"
            exit 2
        fi
    fi

    # test whether the quarter directory is available
    quarterPath="$hostPath/$(date +%Yq%q)"
    if [ -d "$quarterPath" ]; then
        echo "Directory exists: $quarterPath"
    else
        echo "Creating directory: $quarterPath"
        mkdir $quarterPath
        mkStat=$?
        if [[ "$mkStat" != 0 ]]; then
            echo "Error $mkStat: Could not create directory $quarterPath"
            exit 2
        fi
    fi

    # make the final backup directory name using the current date
    today=$(date +%F)
    backupDir="$quarterPath/$today"

    # find the previous backup subdirectory (most recent)
    prevBackup=$(ls -c --classify $quarterPath | egrep '*/$' | sed -n '1p')
    if [ -n "$prevBackup" ]; then
        prevBackup=$quarterPath/${prevBackup::-1}
    fi
    # be sure the backup directory name isn't the same as the previous
    if [ "$backupDir" == "$prevBackup" ]; then
        prevBackup=$(ls -c --classify $hostPath | egrep '*/$' | sed -n '2p')
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

    # test whether the backup directory is available
    if [ -d "$backupDir" ]; then
        echo "Directory exists: $backupDir"
    else
        echo "Creating directory: $backupDir"
        mkdir $backupDir
        mkStat=$?
        if [[ "$mkStat" != 0 ]]; then
            echo "Error $mkStat: Could not create directory $backupDir"
            exit 2
        fi
    fi

    # do the backup
    startTime=$(date +%s)
    echo "Backup starting at $(date --date=@$startTime "+%F %T")" | tee -a $logFile
    echo "Backing up to $backupDir" | tee -a $logFile
    echo "Log file is $logFile" | tee -a $logFile
    if [ -n "$prevBackup" ]; then
        echo "This is an incremental backup" | tee -a $logFile
        echo "Previous backup used as link-dest: $prevBackup" | tee -a $logFile
    else
        echo "No previous backup found, this is a full backup" | tee -a $logFile
        echo "Limited rsync logging for full backup" | tee -a $logFile
    fi
    echo "Command is: rsync $OPTS $SRC $backupDir" | tee -a $logFile
    rsync $OPTS $SRC $backupDir
    echo "Wait for sync..." | tee -a $logFile
    sync
    endTime=$(date +%s)
    lapse=$(($endTime - $startTime))
    echo "Backup finished at $(date --date=@$endTime "+%F %T") Lapse $(date -u --date=@$lapse "+%H:%M:%S")" | tee -a $logFile
    echo -e "--------------------------------\n" >>$logFile
fi
