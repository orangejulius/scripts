#!/bin/bash -ex

cmd1="rsync -avH --delete --exclude=snapshots --progress /run/media/spectre256/photos/ /run/media/spectre256/photos-btrfs/"
$cmd1

DATE=`date +%Y-%m-%d:%H:%M:%S`

cmd2="sudo btrfs subvolume snapshot /run/media/spectre256/photos-btrfs /run/media/spectre256/photos-btrfs/snapshots/${DATE}"
$cmd2
