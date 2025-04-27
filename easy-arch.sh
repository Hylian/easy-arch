#!/usr/bin/env -S bash -e

# iwctl
# [iwd]# device list
# [iwd]# station device scan
# [iwd]# station device get-networks
# [iwd]# station device connect SSID
#
# curl --output easyarch.sh -L https://easyarch.tokilabs.co
# chmod +x easyarch.sh
# ./easyarch.sh

clear

# Cosmetics (colours for text).
BOLD='\e[1m'
BRED='\e[91m'
BBLUE='\e[34m'
BGREEN='\e[92m'
BYELLOW='\e[93m'
RESET='\e[0m'

# Pretty print (function).
info_print () {
    echo -e "${BOLD}${BGREEN}[ ${BYELLOW}•${BGREEN} ] $1${RESET}"
}

# Pretty print for input (function).
input_print () {
    echo -ne "${BOLD}${BYELLOW}[ ${BGREEN}•${BYELLOW} ] $1${RESET}"
}

# Alert user of bad input (function).
error_print () {
    echo -e "${BOLD}${BRED}[ ${BBLUE}•${BRED} ] $1${RESET}"
}

rotation_selector () {
    info_print "Rotate the display?"
    info_print "0) No (default)"
    info_print "1) 90 clockwise"
    info_print "2) 180"
    info_print "3) 90 counter-clockwise"
    read -r rotation_choice
    if ! [[ "$rotation_choice" =~ ^[0-3]$ ]]; then
        rotation_choice=0
    fi
    echo "$rotation_choice" > /sys/class/graphics/fbcon/rotate_all
}

# User enters a password for the LUKS Container (function).
lukspass_selector () {
    input_print "Please enter a password for the LUKS container (you're not going to see the password): "
    read -r -s password
    if [[ -z "$password" ]]; then
        echo
        error_print "You need to enter a password for the LUKS Container, please try again."
        return 1
    fi
    echo
    input_print "Please enter the password for the LUKS container again (you're not going to see the password): "
    read -r -s password2
    echo
    if [[ "$password" != "$password2" ]]; then
        error_print "Passwords don't match, please try again."
        return 1
    fi
    return 0
}

# Setting up a password for the user account (function).
userpass_selector () {
    input_print "Please enter name for a user account (enter empty to not create one): "
    read -r username
    if [[ -z "$username" ]]; then
        return 0
    fi
    input_print "Please enter a password for $username (you're not going to see the password): "
    read -r -s userpass
    if [[ -z "$userpass" ]]; then
        echo
        error_print "You need to enter a password for $username, please try again."
        return 1
    fi
    echo
    input_print "Please enter the password again (you're not going to see it): "
    read -r -s userpass2
    echo
    if [[ "$userpass" != "$userpass2" ]]; then
        echo
        error_print "Passwords don't match, please try again."
        return 1
    fi
    return 0
}

# Setting up a password for the root account (function).
rootpass_selector () {
    input_print "Please enter a password for the root user (you're not going to see it): "
    read -r -s rootpass
    if [[ -z "$rootpass" ]]; then
        echo
        error_print "You need to enter a password for the root user, please try again."
        return 1
    fi
    echo
    input_print "Please enter the password again (you're not going to see it): "
    read -r -s rootpass2
    echo
    if [[ "$rootpass" != "$rootpass2" ]]; then
        error_print "Passwords don't match, please try again."
        return 1
    fi
    return 0
}

# Microcode detector (function).
microcode_detector () {
    CPU=$(grep vendor_id /proc/cpuinfo)
    if [[ "$CPU" == *"AuthenticAMD"* ]]; then
        info_print "An AMD CPU has been detected, the AMD microcode will be installed."
        microcode="amd-ucode"
    else
        info_print "An Intel CPU has been detected, the Intel microcode will be installed."
        microcode="intel-ucode"
    fi
}

# User enters a hostname (function).
hostname_selector () {
    input_print "Please enter the hostname: "
    read -r hostname
    if [[ -z "$hostname" ]]; then
        error_print "You need to enter a hostname in order to continue."
        return 1
    fi
    return 0
}

rotation_selector

# Setting up keyboard layout.
info_print "Setting console layout to 'us'"
loadkeys "us"

# Choosing the target for the installation.
info_print "Available disks for the installation:"
PS3="Please select the number of the corresponding disk (e.g. 1): "
select ENTRY in $(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd");
do
    DISK="$ENTRY"
    info_print "Arch Linux will be installed on the following disk: $DISK"
    break
done


# Setting up LUKS password.
until lukspass_selector; do : ; done

# User choses the hostname.
until hostname_selector; do : ; done

# User sets up the user/root passwords.
until userpass_selector; do : ; done
until rootpass_selector; do : ; done

# Clear the partition table
echo "Clearing the partition table on $DISK..."
sgdisk --zap-all "$DISK"

# Create the EFI partition (1GB)
echo "Creating 1GB EFI partition..."
sgdisk --new=1:0:+1G --typecode=1:EF00 --change-name=1:"ESP" "$DISK"

# Create the CRYPTROOT partition with the rest of the disk
echo "Creating CRYPTROOT partition with remaining space..."
sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:"CRYPTROOT" "$DISK"

# Print the new partition table
echo "New partition table:"
sgdisk --print "$DISK"

ESP="/dev/disk/by-partlabel/ESP"
CRYPTROOT="/dev/disk/by-partlabel/CRYPTROOT"

# Informing the Kernel of the changes.
info_print "Informing the Kernel about the disk changes."
partprobe "$DISK"

info_print "Formatting the EFI Partition as FAT32."
mkfs.fat -F 32 "$ESP" &>/dev/null

# Creating a LUKS Container for the root partition.
info_print "Creating LUKS Container for the root partition."
echo -n "$password" | cryptsetup luksFormat --perf-no_read_workqueue --perf-no_write_workqueue --type luks2 --cipher aes-xts-plain64 --key-size 512 --iter-time 2000 --pbkdf argon2id --hash sha3-512 "$CRYPTROOT" -d - &>/dev/null
echo -n "$password" | cryptsetup --allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent open "$CRYPTROOT" cryptroot -d -
BTRFS="/dev/mapper/cryptroot"

# Formatting the LUKS Container as BTRFS.
info_print "Formatting the LUKS container as BTRFS."
mkfs.btrfs "$BTRFS" &>/dev/null
mount "$BTRFS" /mnt

# Creating BTRFS subvolumes.
info_print "Creating BTRFS subvolumes."
subvols=(root snapshots pkg home tmp srv swap btrfs)
for subvol in '' "${subvols[@]}"; do
    btrfs su cr /mnt/@"$subvol"
done

info_print "Subvolume creation complete."
ls /mnt

# Mounting the newly created subvolumes.
umount /mnt

info_print "Mounting the newly created subvolumes."
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
btrfs filesystem mkswapfile --size 68g --uuid clear /mnt/.swapvol/swapfile
swapon /mnt/.swapvol/swapfile

mount "${ESP}" /mnt/boot/

# Checking the microcode to install.
microcode_detector

# Pacstrap (setting up a base sytem onto the new root).
info_print "Installing the base system (it may take a while)."
sed -Ei 's/^#(Color)$/\1\nILoveCandy/;s/^#(ParallelDownloads).*/\1 = 10/' /etc/pacman.conf
pacstrap -K /mnt base linux "$microcode" linux-firmware linux-headers btrfs-progs mesa rsync efibootmgr reflector snap-pac zram-generator sudo base-devel gcc git

# Setting up the hostname.
echo "$hostname" > /mnt/etc/hostname

# Generating /etc/fstab.
info_print "Generating a new fstab."
genfstab -U /mnt >> /mnt/etc/fstab

# Configure selected locale and console keymap
locale="en_US.UTF-8"
sed -i "/^#$locale/s/^#//" /mnt/etc/locale.gen
echo "LANG=$locale" > /mnt/etc/locale.conf

kblayout="us"
echo "KEYMAP=$kblayout" > /mnt/etc/vconsole.conf

# Setting hosts file.
info_print "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF

# Setting up the network.
info_print "Setting up network."
pacstrap /mnt networkmanager iwd >/dev/null
systemctl enable NetworkManager --root=/mnt &>/dev/null
echo "[device]" > /mnt/etc/NetworkManager/conf.d/nm.conf
echo "wifi.backend=iwd" >> /mnt/etc/NetworkManager/conf.d/nm.conf

# Configuring /etc/mkinitcpio.conf.
info_print "Configuring /etc/mkinitcpio.conf."
sed -i 's/BINARIES=()/BINARIES=("\/usr\/bin\/btrfs")/' /mnt/etc/mkinitcpio.conf
sed -i 's/MODULES=()/MODULES=(amdgpu)/' /mnt/etc/mkinitcpio.conf
sed -i 's/#COMPRESSION="lz4"/COMPRESSION="lz4"/' /mnt/etc/mkinitcpio.conf
sed -i 's/#COMPRESSION_OPTIONS=()/COMPRESSION_OPTIONS=(-9)/' /mnt/etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*$/HOOKS=(base systemd autodetect modconf block sd-encrypt resume filesystems keyboard fsck)/' /mnt/etc/mkinitcpio.conf

echo 'PRUNENAMES = ".snapshots"' >> /mnt/etc/updatedb.conf

# ============
# BEGIN CHROOT
# ============
info_print "Entering chroot."
arch-chroot /mnt /bin/bash -e <<EOF

# Setting up timezone.
echo "Setting timezone to New_York."
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime &>/dev/null

# Setting up clock.
echo "Setting up clock."
hwclock --systohc

# Generating locales.
echo "Generating locales."
locale-gen &>/dev/null

# Generating a new initramfs.
echo "Generating initramfs."
mkinitcpio -P

echo "Configuring snapper."
# Snapper configuration.
umount /.snapshots
rm -r /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots &>/dev/null
mkdir /.snapshots
mount -a &>/dev/null
chmod 750 /.snapshots

echo "Installing paru."
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si
cd .. && sudo rm -dR paru

echo "Installing user applications."
paru -S --noconfirm 1password 1password-cli 7zip adobe-source-code-pro-fonts adobe-source-sans-fonts adwaita-cursors adwaita-icon-theme alsa-utils antigen anything-sync-daemon arm-none-eabi-binutils arm-none-eabi-gcc arm-none-eabi-gdb arm-none-eabi-newlib avahi bat bear betterbird-bin binutils binwalk blueman bluez bluez-libs breeze breeze-gtk breeze-icons bubblewrap catppuccin-gtk-theme-frappe ccache chezmoi cifs-utils clang cmake curl dfu-programmer dfu-util direnv discord dolphin dolphin-plugins dropbox dunst elfutils esptool ethtool everforest-gtk-theme-git expac eza fd firefox fonts-meta-base fonts-meta-extended-lt fzf ghostty ghostty-shell-integration ghostty-terminfo gimp git git-delta gnome-calculator gnome-disk-utility gnome-keyring grimshot handbrake hexyl htop hunspell hunspell-en_us imagemagick imv jq kanshi mpv neofetch neovim obsidian parted pavucontrol qdirstat raindrop ripgrep rpi-imager rsync signal-desktop starship stgit strace suitesparse swaybg swayfx-git swayidle swaylock tag-ag tex-gyre-fonts texinfo tofi ttc-iosevka ttf-anonymous-pro ttf-bitstream-vera ttf-caladea ttf-carlito ttf-cascadia-code ttf-courier-prime ttf-dejavu ttf-droid ttf-fira-code ttf-fira-mono ttf-fira-sans ttf-font-awesome ttf-gelasio ttf-gelasio-ib ttf-hack ttf-heuristica ttf-ibm-plex ttf-ibmplex-mono-nerd ttf-impallari-cantora ttf-iosevka-nerd ttf-liberation ttf-merriweather ttf-merriweather-sans ttf-opensans ttf-oswald ttf-quintessential ttf-signika ttf-ubuntu-font-family ttf-ubuntu-mono-nerd ttf-unifont udiskie udisks2 unrar unzip waybar wdisplays wget wireplumber wl-clipboard wol wpa_supplicant xdg-desktop-portal-wlr zathura zathura-pdf-mupdf zellij zen-browser-bin zip zola zotero-bin zoxide zsh zsh-autosuggestions

echo "Dotfile setup..."
cd ~
chezmoi init --apply Hylian
EOF
info_print "Exiting chroot."
# ==========
# END CHROOT
# ==========

mkdir /mnt/etc/pacman.d/hooks

info_print "Creating /etc/pacman.d/hooks/50-bootbackup.hook to backup /boot when pacman transactions are made."
cat > /mnt/etc/pacman.d/hooks/50-bootbackup.hook <<EOF
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Path
Target = usr/lib/modules/*/vmlinuz

[Action]
Depends = rsync
Description = Backing up /boot...
When = PostTransaction
Exec = /usr/bin/rsync -a --delete /boot /.bootbackup
EOF

info_print "Enabling autologin."
mkdir -p /mnt/etc/systemd/system/getty@tty.service.d/
cat > /mnt/etc/systemd/system/getty@tty.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $username - zsh
Type=simple
Environment=XDG_SESSION_TYPE=wayland
EOF

info_print "Entering chroot."
arch-chroot /mnt /bin/bash -e <<EOF

cd /tmp
curl -LJO https://raw.githubusercontent.com/osandov/osandov-linux/master/scripts/btrfs_map_physical.c
gcc -O2 -o btrfs_map_physical btrfs_map_physical.c
rm btrfs_map_physical.c
mv btrfs_map_physical /usr/local/bin
EOF

info_print "Configuring bootloader."
UUID=$(blkid -s UUID -o value "$CRYPTROOT")
rotation_kernel_option=''
if [[ $rotation_choice != 0 ]]; then
    rotation_kernel_option="fbcon=rotate:$rotation_choice"
fi

arch-chroot /mnt bootctl install

cat << EOF > /mnt/etc/pacman.d/hooks/95-systemd-boot.hook
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Gracefully upgrading systemd-boot...
When = PostTransaction
Exec = /usr/bin/systemctl restart systemd-boot-update.service
EOF

cat << EOF > /mnt/boot/loader/loader.conf
default  arch.conf
timeout  0
console-mode max
editor   no
EOF

cat << EOF > /mnt/boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options rd.luks.name=$UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rootfstype=btrfs resume_offset=$( echo "$(/mnt/usr/local/bin/btrfs_map_physical /mnt/.swapvol/swapfile | head -n2 | tail -n1 | awk '{print $6}') / $(getconf PAGESIZE) " | bc) rw quiet nmi_watchdog=0 add_efi_memmap initrd=/amd-ucode.img $rotation_kernel_option
EOF

# Setting root password.
info_print "Setting root password."
echo "root:$rootpass" | arch-chroot /mnt chpasswd

# Setting user password.
if [[ -n "$username" ]]; then
    echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
    info_print "Adding the user $username to the system with root privilege."
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"
    info_print "Setting user password for $username."
    echo "$username:$userpass" | arch-chroot /mnt chpasswd
fi

# Laptop Battery Life Improvements
echo "vm.dirty_writeback_centisecs = 6000" > /mnt/etc/sysctl.d/dirty.conf
if [ $(lsmod | grep '^iwl.vm' | awk '{print $1}') == "iwlmvm" ]; then echo "options iwlwifi power_save=1" > /mnt/etc/modprobe.d/iwlwifi.conf; echo "options iwlmvm power_scheme=3" >> /mnt/etc/modprobe.d/iwlwifi.conf; fi
if [ $(lsmod | grep '^iwl.vm' | awk '{print $1}') == "iwldvm" ]; then echo "options iwldvm force_cam=0" >> /mnt/etc/modprobe.d/iwlwifi.conf; fi

# ZRAM configuration.
info_print "Configuring ZRAM."
cat > /mnt/etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram, 8192)
EOF

# Pacman eye-candy features.
info_print "Enabling colours, animations, and parallel downloads for pacman."
sed -Ei 's/^#(Color)$/\1\nILoveCandy/;s/^#(ParallelDownloads).*/\1 = 10/' /mnt/etc/pacman.conf

# Enabling various services.
info_print "Enabling Reflector, automatic snapshots, BTRFS scrubbing and systemd-oomd."
services=(reflector.timer snapper-timeline.timer snapper-cleanup.timer btrfs-scrub@-.timer btrfs-scrub@home.timer btrfs-scrub@var-log.timer btrfs-scrub@\\x2esnapshots.timer systemd-oomd)
for service in "${services[@]}"; do
    systemctl enable "$service" --root=/mnt &>/dev/null
done

# Finishing up.
info_print "Done!"
