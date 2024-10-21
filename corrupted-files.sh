#!/bin/bash
CORRUPTED_UNRECOVERABLE=()
CORRUPTED_READABLE=()
CORRUPTED_TORRENTS=()

BTRFS_MOUNT=/srv

# This script looks in the journal for checksum errors and lists the files that are corrupted,
# And then determines if the file is still even readable.

# If the file is a video file, it will ffprobe the file to see if it is still playable, if not, it will be marked as unrecoverable
# Corrupted video files will be kept as-is as they may still be playable, but the user should be informed
# Else the file will be md5summed to see if it is still readable, if not, it will be marked as unrecoverable

function btrfs_stats_wipe {
    sudo btrfs device stats --reset $BTRFS_MOUNT
}

function get_checksum_errors {
    sudo journalctl --dmesg --grep 'checksum error'
}

function corrupted_files {
    local errors=$(get_checksum_errors)
    local files=()
    while IFS= read -r line; do
        local file=$(echo $line | awk '{for (i=31; i<=NF; i++) printf $i " "; print ""}' | sed 's/..$//')
        files+=("$file")
    done <<<"$errors"
    printf "%s\n" "${files[@]}" | sort -u

}

function list_files {
    local IFS=$'\n'
    corrupted_files | while read line; do
        echo "$BTRFS_MOUNT/$line"
    done
}

function check_file {
    local file=$1
    echo -e "Checking file [\e[34m$file\e[0m]"
    if [ ! -f $file ]; then
        echo -e "File [\e[34m$file\e[0m] does not exist anymore, skipping"
        return
    fi

    # If file is in /srv/downloads, just inform the user
    if [[ $file == /srv/downloads/* ]]; then
        # check if in trash folder
        if [[ $file == /srv/downloads/.Trash-* ]]; then
            echo -e "File [\e[34m$file\e[0m] is in trash folder, skipping"
            return
        fi
        echo -e "File [\e[34m$file\e[0m] is in /srv/downloads, Redownload or force recheck using torrent client"
        CORRUPTED_TORRENTS+=($file)
        return

    # If video file in mkv format, check if still works
    elif [[ $file == *.mkv ]]; then
        echo -e "Checking if [\e[34m$file\e[0m] is still playable"
        if ! ffprobe $file >/dev/null 2>&1; then
            echo -e "File [\e[34m$file\e[0m] is corrupted, cannot read. We should probably delete it"
            CORRUPTED_UNRECOVERABLE+=($file)
            return 1
        else
            echo -e "File [\e[34m$file\e[0m] is still playable, we can probably still play it..."
            CORRUPTED_READABLE+=($file)
            return
        fi
    else
        if ! sudo md5sum $file >/dev/null 2>&1; then
            echo -e "File [\e[34m$file\e[0m] is corrupted, cannot read. We should probably delete it"
            CORRUPTED_UNRECOVERABLE+=($file)
            return 1
        fi
    fi
}
FILE_LIST=$(list_files)

function check_all_files {
    local IFS=$'\n'
    for file in $FILE_LIST; do
        echo
        check_file $file
        echo
    done
}

echo "Corrupted files:"
echo

echo "$FILE_LIST"
echo

echo "Checking files..."

check_all_files

if [ ${#CORRUPTED_READABLE[@]} -gt 0 ]; then
    # Save the list to corrupted-readable.txt
    echo "Corrupted but still readable files:"
    echo
    printf "%s\n" "${CORRUPTED_READABLE[@]}"

    # save the file list to corrupted-readable.txt
    echo "Saving list to corrupted-readable.txt"

    printf "%s\n" "${CORRUPTED_READABLE[@]}" >corrupted-readable.txt

fi

if [ ${#CORRUPTED_UNRECOVERABLE[@]} -gt 0 ]; then
    echo "Unrecoverable corrupted files:"
    echo
    printf "%s\n" "${CORRUPTED_UNRECOVERABLE[@]}"
    echo

    echo "Do you want to delete these files? [y/N]"

    read -r answer

    if [[ $answer == "y" ]]; then
        for file in "${CORRUPTED_UNRECOVERABLE[@]}"; do
            echo -e "Deleting file [\e[31m$file\e[0m]"
            sudo rm -f $file
        done
    else
        echo "Files not deleted, you can delete them manually"
    fi
fi

if [ ${#CORRUPTED_TORRENTS[@]} -gt 0 ]; then
    echo "Corrupted downloaded files:"
    echo
    printf "%s\n" "${CORRUPTED_TORRENTS[@]}"
    echo "Please redownload or force recheck using torrent client"

fi

echo

echo "Would you like to wipe btrfs stats? [y/N]"
read -r answer

if [[ $answer == "y" ]]; then
    btrfs_stats_wipe
fi
