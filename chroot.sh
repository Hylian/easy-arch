#!/usr/bin/env -S bash -e

CRYPTROOT="/dev/disk/by-partlabel/CRYPTROOT"
ESP="/dev/disk/by-partlabel/EFI\\x20system\\x20partition"
cryptsetup open "$CRYPTROOT" cryptroot
BTRFS="/dev/mapper/cryptroot"

mount "$ESP" /mnt/boot/

mount -o noatime,nodiratime,compress=zstd,compress-force=zstd:3,commit=120,ssd,discard=async,autodefrag,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{root,boot,home,var/cache/pacman/pkg,var/tmp,.snapshots,.swapvol,btrfs,srv}
mount -o noatime,nodiratime,compress=zstd,compress-force=zstd:3,commit=120,ssd,discard=async,autodefrag,subvol=@root /dev/mapper/cryptroot /mnt/root
mount -o noatime,nodiratime,compress=zstd,compress-force=zstd:3,compress-force=zstd:3,commit=120,ssd,discard=async,autodefrag,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,nodiratime,compress=zstd,compress-force=zstd:3,commit=120,ssd,discard=async,autodefrag,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o noatime,nodiratime,compress=zstd,compress-force=zstd:3,commit=120,ssd,discard=async,autodefrag,subvol=@tmp /dev/mapper/cryptroot /mnt/var/tmp
mount -o noatime,nodiratime,compress=zstd,compress-force=zstd:3,commit=120,ssd,discard=async,autodefrag,subvol=@srv /dev/mapper/cryptroot /mnt/srv
mount -o noatime,nodiratime,compress=zstd,compress-force=zstd:3,commit=120,ssd,discard=async,autodefrag,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount -o ssd,discard=async,subvol=@swap /dev/mapper/cryptroot /mnt/.swapvol
mount -o noatime,nodiratime,compress=zstd,compress-force=zstd:3,commit=120,ssd,discard=async,autodefrag,subvolid=5 /dev/mapper/cryptroot /mnt/btrfs
chmod 750 /mnt/root

# Create Swapfile
swapon /mnt/.swapvol/swapfile

mount "${ESP}" /mnt/boot/

arch-chroot /mnt
