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

# Cleaning the TTY.
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

# Selecting a kernel to install (function).
kernel_selector () {
    info_print "List of kernels:"
    info_print "1) Stable: Vanilla Linux kernel with a few specific Arch Linux patches applied"
    info_print "2) Hardened: A security-focused Linux kernel"
    info_print "3) Longterm: Long-term support (LTS) Linux kernel"
    info_print "4) Zen Kernel: A Linux kernel optimized for desktop usage"
    input_print "Please select the number of the corresponding kernel (e.g. 1): "
    read -r kernel_choice
    case $kernel_choice in
        1 ) kernel="linux"
            return 0;;
        2 ) kernel="linux-hardened"
            return 0;;
        3 ) kernel="linux-lts"
            return 0;;
        4 ) kernel="linux-zen"
            return 0;;
        * ) kernel="linux"
            info_print "Defaulting to 'linux'"
            return 0;;
    esac
}

# Selecting a way to handle internet connection (function).
network_selector () {
    info_print "Network utilities:"
    info_print "1) IWD: Utility to connect to networks written by Intel (WiFi-only, built-in DHCP client)"
    info_print "2) NetworkManager: Universal network utility (both WiFi and Ethernet, highly recommended)"
    info_print "3) wpa_supplicant: Utility with support for WEP and WPA/WPA2 (WiFi-only, DHCPCD will be automatically installed)"
    info_print "4) dhcpcd: Basic DHCP client (Ethernet connections or VMs)"
    info_print "5) I will do this on my own (only advanced users)"
    input_print "Please select the number of the corresponding networking utility (e.g. 1): "
    read -r network_choice
    if ! [[ "$network_choice" =~ ^[1-5]$ ]]; then
        info_print "Defaulting to NetworkManager (with iwd backend)"
        network_choice=2
        return 0
    fi
    return 0
}

# Installing the chosen networking method to the system (function).
network_installer () {
    case $network_choice in
        1 ) info_print "Installing and enabling IWD."
            pacstrap /mnt iwd >/dev/null
            systemctl enable iwd --root=/mnt &>/dev/null
            ;;
        2 ) info_print "Installing and enabling NetworkManager."
            pacstrap /mnt networkmanager iwd >/dev/null
            systemctl enable NetworkManager --root=/mnt &>/dev/null
            echo "[device]" > /mnt/etc/NetworkManager/conf.d/nm.conf
            echo "wifi.backend=iwd" >> /mnt/etc/NetworkManager/conf.d/nm.conf
            ;;
        3 ) info_print "Installing and enabling wpa_supplicant and dhcpcd."
            pacstrap /mnt wpa_supplicant dhcpcd >/dev/null
            systemctl enable wpa_supplicant --root=/mnt &>/dev/null
            systemctl enable dhcpcd --root=/mnt &>/dev/null
            ;;
        4 ) info_print "Installing dhcpcd."
            pacstrap /mnt dhcpcd >/dev/null
            systemctl enable dhcpcd --root=/mnt &>/dev/null
    esac
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

# User chooses the locale (function).
locale_selector () {
    #input_print "Please insert the locale you use (format: xx_XX. Enter empty to use en_US, or \"/\" to search locales): " locale
    #read -r locale
    locale=''
    case "$locale" in
        '') locale="en_US.UTF-8"
            info_print "$locale will be the default locale."
            return 0;;
        '/') sed -E '/^# +|^#$/d;s/^#| *$//g;s/ .*/ (Charset:&)/' /etc/locale.gen | less -M
                clear
                return 1;;
        *)  if ! grep -q "^#\?$(sed 's/[].*[]/\\&/g' <<< "$locale") " /etc/locale.gen; then
                error_print "The specified locale doesn't exist or isn't supported."
                return 1
            fi
            return 0
    esac
}

# User chooses the console keyboard layout (function).
keyboard_selector () {
    input_print "Please insert the keyboard layout to use in console (enter empty to use US, or \"/\" to look up for keyboard layouts): "
    read -r kblayout
    case "$kblayout" in
        '') kblayout="us"
            info_print "The standard US keyboard layout will be used."
            return 0;;
        '/') localectl list-keymaps
             clear
             return 1;;
        *) if ! localectl list-keymaps | grep -Fxq "$kblayout"; then
               error_print "The specified keymap doesn't exist."
               return 1
           fi
        info_print "Changing console layout to $kblayout."
        loadkeys "$kblayout"
        return 0
    esac
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

ESP="${DISK}p1"
info_print "DISK=${DISK} ESP=${ESP}"
input_print "Using ${ESP} as the EFI boot partition. Is this correct [Y/n]?: "
read -r boot_response
if [[ "${boot_response,,}" =~ ^(no|N|n|NO|no)$ ]]; then
    error_print "Quitting."
    exit
fi

# Setting up LUKS password.
until lukspass_selector; do : ; done

# Setting up the kernel.
until kernel_selector; do : ; done

# User choses the network.
until network_selector; do : ; done

# User choses the locale.
until locale_selector; do : ; done

# User choses the hostname.
until hostname_selector; do : ; done

# User sets up the user/root passwords.
until userpass_selector; do : ; done
until rootpass_selector; do : ; done

echo -e "$(parted $DISK unit MB print free)"
input_print "Installing to largest free space. Is this correct [Y/n]?: "
read -r free_space_response
if [[ "${free_space_response,,}" =~ ^(no|N|n|NO|no)$ ]]; then
    error_print "Quitting."
    exit
fi

info_print "OK! Creating CRYPTROOT partition on $DISK."
sgdisk -n 0:0:0 -c 0:"CRYPTROOT" "$DISK"
CRYPTROOT="/dev/disk/by-partlabel/CRYPTROOT"

echo -e "$(parted $DISK unit MB print free)"
input_print "Partition created. Look good [Y/n]?: "
read -r post_partition_response
if [[ "${post_partition_response,,}" =~ ^(no|N|n|NO|no)$ ]]; then
    error_print "Quitting."
    exit
fi

# Informing the Kernel of the changes.
info_print "Informing the Kernel about the disk changes."
partprobe "$DISK"

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

rm -rf /mnt/boot/efi/EFI/refind
rm -f /mnt/boot/amd-ucode.img

# Pacstrap (setting up a base sytem onto the new root).
info_print "Installing the base system (it may take a while)."
pacstrap -K /mnt base "$kernel" "$microcode" linux-firmware "$kernel"-headers btrfs-progs mesa rsync efibootmgr refind reflector snap-pac zram-generator sudo

# Setting up the hostname.
echo "$hostname" > /mnt/etc/hostname

# Generating /etc/fstab.
info_print "Generating a new fstab."
genfstab -U /mnt >> /mnt/etc/fstab

# Configure selected locale and console keymap
sed -i "/^#$locale/s/^#//" /mnt/etc/locale.gen
echo "LANG=$locale" > /mnt/etc/locale.conf
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
network_installer

# Configuring /etc/mkinitcpio.conf.
info_print "Configuring /etc/mkinitcpio.conf."
sed -i 's/BINARIES=()/BINARIES=("\/usr\/bin\/btrfs")/' /mnt/etc/mkinitcpio.conf
sed -i 's/MODULES=()/MODULES=(amdgpu)/' /mnt/etc/mkinitcpio.conf
sed -i 's/#COMPRESSION="lz4"/COMPRESSION="lz4"/' /mnt/etc/mkinitcpio.conf
sed -i 's/#COMPRESSION_OPTIONS=()/COMPRESSION_OPTIONS=(-9)/' /mnt/etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*$/HOOKS=(base systemd autodetect modconf block sd-encrypt resume filesystems keyboard fsck)/' /mnt/etc/mkinitcpio.conf

# Configuring the system.
info_print "Configuring the system (timezone, system clock, initramfs, Snapper, refind)."

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
hwclock --systohc

# Generating locales.
echo "Generating locales."
locale-gen &>/dev/null

# Generating a new initramfs.
echo "Generating initramfs."
mkinitcpio -P

echo "Installing and configuring snapper."
sudo pacman -S snapper

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

echo "Installing shim."
paru -S --noconfirm shim-signed

echo "Installing refind."
refind-install --shim /usr/share/shim-signed/shimx64.efi --localkeys
sbsign --key /etc/refind.d/keys/refind_local.key --cert /etc/refind.d/keys/refind_local.crt --output /boot/vmlinuz-linux /boot/vmlinuz-linux

echo "Installing user applications."
paru -S --noconfirm 1password 1password-cli 7zip adobe-source-code-pro-fonts adobe-source-sans-fonts adwaita-cursors adwaita-icon-theme alsa-utils antigen anything-sync-daemon arm-none-eabi-binutils arm-none-eabi-gcc arm-none-eabi-gdb arm-none-eabi-newlib avahi bat bear betterbird-bin binutils binwalk blueman bluez bluez-libs breeze breeze-gtk breeze-icons bubblewrap catppuccin-gtk-theme-frappe ccache cifs-utils clang cmake curl dfu-programmer dfu-util direnv discord dolphin dolphin-plugins dropbox dunst elfutils esptool ethtool everforest-gtk-theme-git expac eza fd firefox fonts-meta-base fonts-meta-extended-lt fzf ghostty ghostty-shell-integration ghostty-terminfo gimp git git-delta gnome-calculator gnome-disk-utility gnome-keyring grimshot handbrake hexyl htop hunspell hunspell-en_us imagemagick imv jq kanshi mpv neofetch neovim obsidian parted pavucontrol qdirstat raindrop ripgrep rpi-imager rsync signal-desktop starship stgit strace suitesparse swaybg swayfx-git swayidle swaylock tag-ag tex-gyre-fonts texinfo tofi ttc-iosevka ttf-anonymous-pro ttf-bitstream-vera ttf-caladea ttf-carlito ttf-cascadia-code ttf-courier-prime ttf-dejavu ttf-droid ttf-fira-code ttf-fira-mono ttf-fira-sans ttf-font-awesome ttf-gelasio ttf-gelasio-ib ttf-hack ttf-heuristica ttf-ibm-plex ttf-ibmplex-mono-nerd ttf-impallari-cantora ttf-iosevka-nerd ttf-liberation ttf-merriweather ttf-merriweather-sans ttf-opensans ttf-oswald ttf-quintessential ttf-signika ttf-ubuntu-font-family ttf-ubuntu-mono-nerd ttf-unifont udiskie udisks2 unrar unzip waybar wdisplays wget wireplumber wl-clipboard wol wpa_supplicant xdg-desktop-portal-wlr zathura zathura-pdf-mupdf zellij zen-browser-bin zip zola zotero-bin zoxide zsh zsh-autosuggestions
EOF
info_print "Exiting chroot."
# ==========
# END CHROOT
# ==========

mkdir /mnt/etc/pacman.d/hooks

info_print "Creating /etc/pacman.d/hooks/999-sign_kernel_for_secureboot.hook"
cat << EOF > /mnt/etc/pacman.d/hooks/999-sign_kernel_for_secureboot.hook
"""
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-hardened
Target = linux-zen
[Action]
Description = Signing kernel with Machine Owner Key for Secure Boot
When = PostTransaction
Exec = /usr/bin/find /boot/ -maxdepth 1 -name 'vmlinuz-*' -exec /usr/bin/sh -c '/usr/bin/sbsign --key /etc/refind.d/keys/refind_local.key --cert /etc/refind.d/keys/refind_local.crt --output {} {}'
Depends = sbsigntools
Depends = findutils
Depends = grep
EOF

info_print "Creating /etc/pacman.d/hooks/refind.hook to auto-sign for secure boot"
cat << EOF > /mnt/etc/pacman.d/hooks/refind.hook
[Trigger]
Operation=Upgrade
Type=Package
Target=refind
[Action]
Description = Updating rEFInd on ESP
When=PostTransaction
Exec=/usr/bin/refind-install --shim /usr/share/shim-signed/shimx64.efi --localkeys
EOF

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

info_print "Configuring refind.conf"
UUID=$(blkid -s UUID -o value $CRYPTROOT)
cat << EOF >> /mnt/boot/EFI/refind/refind.conf
    menuentry "Arch Linux" {
        volume   "Arch Linux"
        loader   /vmlinuz-linux
        initrd   /initramfs-linux.img
        options  "rd.luks.name=$UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rootfstype=btrfs rw quiet nmi_watchdog=0 add_efi_memmap initrd=/amd-ucode.img"
        submenuentry "Boot using fallback initramfs" {
            initrd /boot/initramfs-linux-fallback.img
        }
    }
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
info_print "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
