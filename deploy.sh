#!/bin/sh

STORAGE_DEV="/dev/sda"
BOOT_PARTITION="/dev/sda1"
ZFS_PARTITION="/dev/sda2"

PART_LABEL_BOOT="boot"
PART_START_BOOT="1MiB"

PART_LABEL_ZFS="zpool"
PART_START_ZFS="1GiB"

DS_SIZE_SWAP="4G"

ZFS_POOL="storage"
SWAP_FILE="/dev/zvol/${ZFS_POOL}/swap"

# Quit if any errors occured.
set -e

# Block the script until the specific file is available.
wait_for_file () {
  FILE="$1"
  until [ -e "${FILE}" ]; do
    echo "Awaiting: ${FILE}"
    sleep 1
  done
}

# GPT Partition Table
parted -s "${STORAGE_DEV}" mklabel gpt
  
# Setup the Boot Partition
parted -s -a optimal "${STORAGE_DEV}" mkpart "${PART_LABEL_BOOT}" fat32 "${PART_START_BOOT}" \
  "${PART_START_ZFS}"
mkfs.fat -F 32 -n "${PART_LABEL_BOOT}" "${BOOT_PARTITION}"
parted "${STORAGE_DEV}" set 1 boot on
parted "${STORAGE_DEV}" set 1 esp on

# Create the second partition for the system data
parted -s -a optimal "${STORAGE_DEV}" mkpart "${PART_LABEL_ZFS}" "${PART_START_ZFS}" 100%

# Create the storage pool
zpool create -f -O compression=on -O mountpoint=none -O xattr=sa -O acltype=posixacl -o ashift=12 \
  "${ZFS_POOL}" "${ZFS_PARTITION}"

# Create the dataset
zfs create -o mountpoint=legacy "${ZFS_POOL}/root"
zfs create -o mountpoint=legacy "${ZFS_POOL}/var"
zfs create -o mountpoint=legacy "${ZFS_POOL}/nix"
zfs create -o mountpoint=legacy "${ZFS_POOL}/home"
zfs create -o mountpoint=legacy "${ZFS_POOL}/dev-shm"
zfs create -o mountpoint=legacy "${ZFS_POOL}/tmp "

# Configure swap
zfs create "${ZFS_POOL}/swap" -V "${DS_SIZE_SWAP}"
wait_for_file "${SWAP_FILE}"
mkswap "${SWAP_FILE}"
swapon "${SWAP_FILE}"

# Setup the mount points
mount -t zfs "${ZFS_POOL}/root" /mnt
mkdir -p /mnt/boot /mnt/var /mnt/nix /mnt/home /mnt/dev/shm /mnt/tmp

# Mount all the directories
mount -t vfat "${BOOT_PARTITION}" /mnt/boot
mount -t zfs "${ZFS_POOL}/var" /mnt/var
mount -t zfs "${ZFS_POOL}/nix" /mnt/nix
mount -t zfs -o nodev "${ZFS_POOL}/home" /mnt/home
mount -t zfs -o nodev,nosuid,noexec "${ZFS_POOL}/home" /mnt/dev/shm
mount -t zfs -o nodev,nosuid,noexec "${ZFS_POOL}/tmp" /mnt/tmp

# Generate the base nixos configuration.
nixos-generate-config --root /mnt