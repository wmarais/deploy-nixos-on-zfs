#!/bin/sh

HOST_NAME=""
DISK=""
ADM_USER_NAME=""
ADM_USER_PASSWORD=""

# Parse the arguments to the script.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --disk=*)         DISK="${1#*=}"; shift 1;;
    --user=*)         ADM_USER_NAME="${1#*=}"; shift 1;;
    --password=*)     ADM_USER_PASSWORD="${1#*=}"; shift 1;;
    --host-name=*)    HOST_NAME="${1#*=}"; shift 1;;
    *) echo "invalid argument: $1" >&2; exit 1;;
  esac
done

# Quit if any errors occured.
set -e

# Calculate the full path for the partitions.
part_dev_path() {
  if [ "$(echo "${1}" | cut -c 1-7)" = "/dev/sd" ]; then
    echo "${1}${2}"
  elif [ "$(echo "${1}" | cut -c 1-7)" = "/dev/nv" ]; then
    echo "${1}p${2}"
  else
    echo "Dev path invalid: ${1}"
    exit 1
  fi
}

BOOT_PART_LABEL="boot"
BOOT_PART_START="1MiB"
BOOT_PART_INDEX="1"
BOOT_PART_DEV=$(part_dev_path "${DISK}" "${BOOT_PART_INDEX}")

SWAP_PART_LABEL="swap"
SWAP_PART_START="1GiB"
SWAP_PART_INDEX="2"
SWAP_PART_DEV=$(part_dev_path "${DISK}" "${SWAP_PART_INDEX}")

ZFS_PART_LABEL="system"
ZFS_PART_START="3GiB"
ZFS_PART_INDEX="3"
ZFS_PART_DEV=$(part_dev_path "${DISK}" "${ZFS_PART_INDEX}")

ZFS_POOL_NAME="system"

# Block the script until the specific file is available.
wait_for_file () {
  FILE="$1"
  until [ -e "${FILE}" ]; do
    echo "Awaiting: ${FILE}"
    sleep 1
  done
}

echo "CONFIGURATION"
echo "  Disk: ${DISK}"
echo "  Partitions:"
echo "    ${BOOT_PART_LABEL}(${BOOT_PART_DEV}): ${BOOT_PART_START} to ${SWAP_PART_START}"
echo "    ${SWAP_PART_LABEL}(${SWAP_PART_DEV}): ${SWAP_PART_START} to ${ZFS_PART_START}"
echo "    ${ZFS_PART_LABEL}(${ZFS_PART_DEV}): ${ZFS_PART_START} to 100%"

#
# PARTITION TABLE
#
parted -s "${DISK}" mklabel gpt

#
# BOOT
# 
parted -s -a optimal "${DISK}" mkpart "${BOOT_PART_LABEL}" fat32 "${BOOT_PART_START}" \
  "${SWAP_PART_START}"
mkfs.fat -F 32 -n "${BOOT_PART_LABEL}" "${BOOT_PART_DEV}"
parted "${DISK}" set 1 boot on
parted "${DISK}" set 1 esp on

#
# SWAP 
#
parted -s -a optimal "${DISK}" mkpart "${SWAP_PART_LABEL}" linux-swap "${SWAP_PART_START}" \
  "${ZFS_PART_START}"
mkswap "${SWAP_PART_DEV}"
swapon "${SWAP_PART_DEV}"

#
# ZFS
#
parted -s -a optimal "${DISK}" mkpart "${ZFS_PART_LABEL}" "${ZFS_PART_START}" 100%

# Create the storage pool
zpool create -f -O compression=on -O mountpoint=none -O xattr=sa -O acltype=posixacl -o ashift=12 \
  "${ZFS_POOL_NAME}" "${ZFS_PART_DEV}"

# Create the dataset
zfs create -o mountpoint=legacy "${ZFS_POOL_NAME}/root"
zfs create -o mountpoint=legacy "${ZFS_POOL_NAME}/var"
zfs create -o mountpoint=legacy "${ZFS_POOL_NAME}/nix"
zfs create -o mountpoint=legacy "${ZFS_POOL_NAME}/home"
zfs create -o mountpoint=legacy "${ZFS_POOL_NAME}/dev-shm"
zfs create -o mountpoint=legacy "${ZFS_POOL_NAME}/tmp"

#
# DIRECTORY SETUP
#
mount -t zfs "${ZFS_POOL_NAME}/root" /mnt
mkdir -p /mnt/boot /mnt/var /mnt/nix /mnt/home /mnt/dev/shm /mnt/tmp

# Mount all the directories
mount -t vfat "${BOOT_PART_DEV}" /mnt/boot
mount -t zfs "${ZFS_POOL_NAME}/var" /mnt/var
mount -t zfs "${ZFS_POOL_NAME}/nix" /mnt/nix
mount -t zfs -o nodev "${ZFS_POOL_NAME}/home" /mnt/home
mount -t zfs -o nodev,nosuid,noexec "${ZFS_POOL_NAME}/dev-shm" /mnt/dev/shm
mount -t zfs -o nodev,nosuid,noexec "${ZFS_POOL_NAME}/tmp" /mnt/tmp

# Generate the base nixos configuration.
nixos-generate-config --root /mnt

# Copy a nice terminal and editor configuration
cp ./bash.nix /mnt/etc/nixos/
cp ./vim.nix /mnt/etc/nixos/

#
# WRITE CONFIGURATION
#
echo "{ config, lib, pkgs, ... }:
{
    nixpkgs.config.allowUnfree = false;

    imports = [
        ./bash.nix
        ./boot.nix
        ./networking.nix
        ./filesystem.nix
        ./users.nix
        ./vim.nix
    ];

    time.timeZone = \"Australia/Adelaide\";

    # Set the nix store to automatically optimise each Sunday night / Monday morning.
    nix.gc.automatic = true;
    nix.gc.dates = \"weekly\";
    nix.gc.options = \"--delete-old\";

    nix.optimise.automatic = true;
    nix.optimise.dates = [ \"weekly\" ]; 

    system.stateVersion = \"25.05\";
}" > /mnt/etc/nixos/configuration.nix

#
# USERS
#
echo "{ pkgs, ... }:
{
    users.users.root.hashedPassword = \"!\";
    users.users.${ADM_USER_NAME} = {
        isNormalUser = true;
        extraGroups = [ \"wheel\" ];
        shell = pkgs.bash;
        initialHashedPassword = \"$(mkpasswd -m sha-512 "${ADM_USER_PASSWORD}")\";
    };
}" > /mnt/etc/nixos/users.nix

#
# BOOT
#
echo "{ ... }:
{
    boot.initrd.availableKernelModules = [ \"xhci_pci\" \"ahci\" \"ehci_pci\" \"usb_storage\" \"sd_mod\" ];
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
}" > /mnt/etc/nixos/boot.nix

#
# WRITE NETWORK CONFIG
#
echo "{ ... }:
{
    networking = {
      hostId = \"$(cut -c 1-8 < /etc/machine-id )\";
      useDHCP = true;
      hostName = \"${HOST_NAME}\";
      enableIPv6 = false;
    };
}" > /mnt/etc/nixos/networking.nix

#
# WRITE FILE SYSTEM CONFIG
#
echo "{ ... }:
{
    services.zfs = {
        autoScrub = {
            enable = true;
            interval = \"weekly\";
            pools = [ \"${ZFS_POOL_NAME}\" ];
        };
    };

    fileSystems.\"/boot\" = {
        device = \"${BOOT_PART_DEV}\";
        fsType = \"vfat\";
    };

    fileSystems.\"/\" = {
        device = \"${ZFS_POOL_NAME}/root\";
        fsType = \"zfs\";
    };

    fileSystems.\"/var\" = {
        device = \"${ZFS_POOL_NAME}/var\";
        fsType = \"zfs\";
    };

    fileSystems.\"/nix\" = {
        device = \"${ZFS_POOL_NAME}/nix\";
        fsType = \"zfs\";
    };

    fileSystems.\"/home\" = {
        device = \"${ZFS_POOL_NAME}/home\";
        fsType = \"zfs\";
        options = [ \"nodev\" ];
    };

    fileSystems.\"/dev/shm\" = {
        device = \"${ZFS_POOL_NAME}/dev-shm\";
        fsType = \"zfs\";
        options = [ \"nodev\" \"nosuid\" \"noexec\" ];
    };

    fileSystems.\"/tmp\" = {
        device = \"${ZFS_POOL_NAME}/tmp\";
        fsType = \"zfs\";
        options = [ \"nodev\" \"nosuid\" \"noexec\" ];
    };

    swapDevices = [
        { device = \"${SWAP_PART_DEV}\"; }
    ];
}" > /mnt/etc/nixos/filesystem.nix
