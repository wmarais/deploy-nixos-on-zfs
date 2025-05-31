#!/bin/sh

# Quit if any errors occured.
set -e

# GPT Partition Table
parted -s /dev/sda mklabel gpt
  
# Setup the Boot Partition
sudo parted -s -a optimal /dev/sda mkpart ESP fat32 1MiB 1GiB
sudo mkfs.fat -F 32 -n boot /dev/sda1
sudo parted /dev/sda set 1 boot on
sudo parted /dev/sda set 1 esp on

# Create the second partition for the system data
sudo parted -s -a optimal /dev/sda mkpart system 1GiB 100%

# Create the storage pool
sudo zpool create -O compression=on -O mountpoint=none -O xattr=sa \
    -O acltype=posixacl -o ashift=12 storage /dev/sda2

# Create the dataset
zfs create -o mountpoint=legacy storage/root
zfs create -o mountpoint=legacy storage/var
zfs create -o mountpoint=legacy storage/nix
zfs create -o mountpoint=legacy storage/home
zfs create -o mountpoint=legacy storage/dev-shm
zfs create -o mountpoint=legacy storage/tmp -V 2G 

# Coinfigure swap
zfs create  storage/swap -V 4G
mkswap /dev/zvol/storage/swap
swapon /dev/zvol/storage/swap


# Setup the mount points
mount -t zfs storage/root /mnt
mkdir -p /mnt/boot /mnt/var /mnt/nix /mnt/home /mnt/dev/shm /mnt/tmp

# Mount all the directories
mount -t vfat /dev/sda1 /mnt/boot
mount -t zfs storage/var /mnt/var
mount -t zfs storage/nix /mnt/nix
mount -t zfs -o nodev storage/home /mnt/home
mount -t zfs -o nodev,nosuid,noexec storage/home /mnt/dev/shm
mount -t zfs -o nodev,nosuid,noexec storage/tmp /mnt/tmp