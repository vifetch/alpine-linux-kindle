#!/usr/bin/env bash
# DEPENDENCIES
# qemu-user-static is required to run arm software using the "qemu-arm-static" command (I suppose you use this script on a X86_64 computer)

REPO="http://dl-cdn.alpinelinux.org/alpine" # Alpine repo to use
MNT="/mnt/alpine" # Location to mount img to
IMAGE="./alpine.ext3" # Path and name of image file to create
IMAGESIZE=3072 # Image size (in Megabytes)

# ALPINESETUP: Installs XFCE desktop environment, creates a user named "alpine" with password "alpine". Chroots into environment to allow for fs verification and further operations by user

ALPINESETUP="source /etc/profile
echo kindle > /etc/hostname
echo \"nameserver 1.1.1.1\" > /etc/resolv.conf
mkdir /run/dbus
apk update
apk upgrade
cat /etc/alpine-release
apk add xorg-server-xephyr xwininfo xdotool xinput dbus-x11 sudo bash nano git
apk add desktop-file-utils gtk-engines consolekit2 gtk-murrine-engine caja caja-extensions marco
apk add \$(apk search mate -q | grep -v '\-dev' | grep -v '\-lang' | grep -v '\-doc')
apk add \$(apk search -q ttf- | grep -v '\-doc')
apk add onboard
apk add xournalpp lynx htop fastfetch scrot gnome-screenshot
adduser alpine -D
echo -e \"alpine\nalpine\" | passwd alpine
echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers
addgroup sudo
addgroup alpine sudo
su alpine -c \"cd ~
git init
git remote add origin https://github.com/vifetch/alpine_kindle_dotfiles
git pull origin master
git reset --hard origin/master

export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Use a temporary directory for DBUS
eval $(dbus-launch --sh-syntax)

printf "gnome\n" | setup-desktop

gsettings set org.mate.interface window-scaling-factor 2
gsettings set org.gnome.desktop.interface gtk-theme 'HighContrast'
gsettings set org.gnome.desktop.interface icon-theme 'HighContrast'
gsettings set org.gnome.desktop.session idle-delay 0

echo \"You're now dropped into an interactive shell in Alpine, feel free to explore and type exit to leave.\"
sh"

# STARTGUI: This is the script that gets executed inside the container when the GUI is started. Xepyhr is used to render the desktop inside a window, that has the correct name to be displayed in fullscreen by the kindle's awesome windowmanager


STARTGUI='#!/bin/sh
chmod a+w /dev/shm # Otherwise the alpine user cannot use this (needed for chromium)
SIZE=$(xwininfo -root -display :0 | egrep "geometry" | cut -d " "  -f4)
env DISPLAY=:0 Xephyr :1 -title "L:D_N:application_ID:xephyr" -ac -br -screen $SIZE -cc 4 -reset -terminate & sleep 3 && su alpine -c "env DISPLAY=:1 mate-session"
killall Xephyr'


# ENSURE ROOT
# This script needs root access to e.g. mount the image
[ "$(whoami)" != "root" ] && echo "This script needs to be run as root" && exec sudo -- "$0" "$@"


# GETTING APK-TOOLS-STATIC
# Used to bootstrap Alpine Linux. Reads in the APKINDEX what version it is currently to get the correct download link. It is extracted in /tmp and deleted
echo "Determining version of apk-tools-static"
curl "$REPO/v3.22/main/armhf/APKINDEX.tar.gz" --output /tmp/APKINDEX.tar.gz
tar -xzf /tmp/APKINDEX.tar.gz -C /tmp
APKVER="$(cut -d':' -f2 <<<"$(grep -A 5 "P:apk-tools-static" /tmp/APKINDEX | grep "V:")")" # Grep for the version in APKINDEX
rm /tmp/APKINDEX /tmp/APKINDEX.tar.gz /tmp/DESCRIPTION # Remove what we downloaded and extracted
echo "Version of apk-tools-static is: $APKVER"
echo "Downloading apk-tools-static"
curl "$REPO/v3.22/main/armv7/apk-tools-static-$APKVER.apk" --output "/tmp/apk-tools-static.apk"
tar -xvzf "/tmp/apk-tools-static.apk" -C /tmp 2>&1 | grep -v "Ignoring unknown" # extract apk-tools-static to /tmp


# CREATING IMAGE FILE
echo "Creating image file"
dd if=/dev/zero of="$IMAGE" bs=1M count=$IMAGESIZE # Create image file with dd using /dev/zero 
mkfs.ext3 "$IMAGE" # Make ext3 filesystem
tune2fs -i 0 -c 0 "$IMAGE" # Disable automatic checks using tune2fs


# MOUNTING IMAGE
echo "Mounting image"
mkdir -p "$MNT" # Create mount point
mount -o loop -t ext3 "$IMAGE" "$MNT" # Mount ext3 fs to mount point


# BOOTSTRAPPING ALPINE
# The apk tool we extracted earlier is invoked to create the root filesystem of Alpine inside the
# mounted image. We use the arm-version of it to end up with a root filesystem for arm. Also the "edge" repository is used
# to end up with the newest software, some of which is very useful for Kindles
echo "Bootstrapping Alpine"
qemu-arm-static /tmp/sbin/apk.static -X "$REPO/edge/main" -U --allow-untrusted --root "$MNT" --initdb add alpine-base


# COMPLETE IMAGE MOUNTING FOR CHROOT
# Some more things are needed inside the chroot to be able to work in it (for network connection etc.)
mount /dev/ "$MNT/dev/" --bind
mount -t proc none "$MNT/proc"
mount -o bind /sys "$MNT/sys"


# CONFIGURE ALPINE
cp /etc/resolv.conf "$MNT/etc/resolv.conf" # Copy resolv from host for internet connection
# Configure repositories for apk (edge main+community+testing for lots of useful and up-to-date software)
mkdir -p "$MNT/etc/apk"
echo "$REPO/edge/main/
$REPO/edge/community/
$REPO/edge/testing/
$REPO/v3.22/community" > "$MNT/etc/apk/repositories"
# Create the script to start the gui
echo "$STARTGUI" > "$MNT/startgui.sh"
chmod +x "$MNT/startgui.sh"


# CHROOT
# Here we run arm-software inside the Alpine container, and thus we need the qemu-arm-static binary in it
cp $(which qemu-arm-static) "$MNT/usr/bin/"
echo "Chrooting into Alpine"
chroot /mnt/alpine/ qemu-arm-static /bin/sh -c "$ALPINESETUP" # Chroot and run the setup ALPINESETUP
rm "$MNT/usr/bin/qemu-arm-static" # Remove qemu-arm-static on Alpine fs


# UNMOUNT IMAGE & CLEANUP
sync # Sync to disk
kill $(lsof +f -t "$MNT") # Kill remaining processes
echo "Unmounting image"
umount "$MNT/sys" # Unmount in reverse order
umount "$MNT/proc"
umount -lf "$MNT/dev"
umount "$MNT"
while [[ $(mount | grep "$MNT") ]]
do
	echo "Alpine is still mounted, please wait.."
	sleep 3
	umount "$MNT"
done
echo "Alpine unmounted"

echo "Cleaning up"
rm /tmp/apk-tools-static.apk
rm -r /tmp/sbin
