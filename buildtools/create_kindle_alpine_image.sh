#!/usr/bin/env bash
# DEPENDENCIES
# qemu-user-static is required to run arm software using the "qemu-arm-static" command
# This script runs on x86_64 host to create an ARM image for Kindle Paperwhite 5

REPO="http://dl-cdn.alpinelinux.org/alpine" # Alpine repo to use
MNT="/mnt/alpine" # Location to mount img to
IMAGE="./alpine.ext3" # Path and name of image file to create
IMAGESIZE=3072 # Image size (in Megabytes)

# ALPINESETUP: Installs MATE desktop environment for Kindle Paperwhite 5 (ARMv7/ARMHF)
# Creates a user named "alpine" with password "alpine"

ALPINESETUP=$(cat << 'EOF'
source /etc/profile
echo kindle > /etc/hostname
echo "nameserver 1.1.1.1" > /etc/resolv.conf
mkdir -p /run/dbus

# Update and install essential packages
apk update
apk upgrade
echo "Alpine version: $(cat /etc/alpine-release)"

# Install X11 and desktop infrastructure
apk add xorg-server-xephyr xwininfo xdotool xinput dbus-x11 sudo bash nano git
apk add desktop-file-utils gtk-engines gtk-murrine-engine

# Install MATE desktop for ARM (correct for Paperwhite 5)
apk add mate-desktop mate-terminal mate-panel mate-session-manager
apk add mate-control-center mate-system-monitor mate-notification-daemon
apk add caja caja-extensions marco

# Install fonts
apk add ttf-dejavu ttf-liberation font-noto-emoji

# Create user with password
adduser -D -s /bin/bash alpine
echo "alpine:alpine123" | chpasswd

# Configure sudo
echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers
addgroup wheel
adduser alpine wheel

# Install additional applications
apk add xournalpp lynx htop fastfetch scrot onboard

# Switch to alpine user for dotfiles configuration
su - alpine << 'EOALPINE'
cd ~
git init -q
git config --global init.defaultBranch main
git remote add origin https://github.com/vifetch/alpine_kindle_dotfiles
git pull origin master
git reset --hard origin/master

# Apply dconf settings
if [ -f ~/.config/org_mate.dconf.dump ]; then
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
    dconf load /org/mate/ < ~/.config/org_mate.dconf.dump 2>/dev/null || true
fi
if [ -f ~/.config/org_onboard.dconf.dump ]; then
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
    dconf load /org/onboard/ < ~/.config/org_onboard.dconf.dump 2>/dev/null || true
fi
EOALPINE

echo "Setup complete. Type 'exit' to finish image creation."
/bin/sh
EOF
)

# STARTGUI: Script executed when GUI starts on Kindle
# Xephyr renders desktop in a window that Kindle's window manager displays fullscreen

STARTGUI=$(cat << 'EOF'
#!/bin/sh
# Ensure shared memory is writable
chmod a+w /dev/shm 2>/dev/null || true

# Get display resolution from main X server
SIZE=$(xwininfo -root -display :0 | grep "geometry" | cut -d " " -f4)
[ -z "$SIZE" ] && SIZE="800x600"  # Fallback

# Start Xephyr with Kindle-specific window title
env DISPLAY=:0 Xephyr :1 -title "L:D_N:application_ID:xephyr" -ac -br -screen "$SIZE" -cc 4 -reset -terminate &
XEPHYR_PID=$!
sleep 3  # Wait for Xephyr to start

# Start MATE session as alpine user
su - alpine -c "
    export DISPLAY=:1
    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=MATE
    mate-session
" &
MATE_PID=$!

# Wait for session to end
wait $MATE_PID 2>/dev/null || true

# Cleanup
kill $XEPHYR_PID 2>/dev/null || true
EOF
)

# ENSURE ROOT
[ "$(whoami)" != "root" ] && echo "This script needs to be run as root" && exec sudo -- "$0" "$@"

# GETTING APK-TOOLS-STATIC for ARMv7 (Paperwhite 5)
echo "Determining version of apk-tools-static for ARMv7"
curl -s "$REPO/latest-stable/main/armv7/APKINDEX.tar.gz" --output /tmp/APKINDEX.tar.gz
tar -xzf /tmp/APKINDEX.tar.gz -C /tmp
APKVER="$(cut -d':' -f2 <<<"$(grep -A 5 "P:apk-tools-static" /tmp/APKINDEX | grep "V:")")"
rm /tmp/APKINDEX /tmp/APKINDEX.tar.gz /tmp/DESCRIPTION
echo "Version of apk-tools-static is: $APKVER"

echo "Downloading apk-tools-static for ARMv7"
curl -s "$REPO/latest-stable/main/armv7/apk-tools-static-$APKVER.apk" --output "/tmp/apk-tools-static.apk"
tar -xzf "/tmp/apk-tools-static.apk" -C /tmp 2>&1 | grep -v "Ignoring unknown"

# CREATING IMAGE FILE
echo "Creating image file ($IMAGESIZE MB)"
dd if=/dev/zero of="$IMAGE" bs=1M count=$IMAGESIZE status=progress
mkfs.ext3 "$IMAGE"
tune2fs -i 0 -c 0 "$IMAGE"

# MOUNTING IMAGE
echo "Mounting image"
mkdir -p "$MNT"
mount -o loop -t ext3 "$IMAGE" "$MNT"

# BOOTSTRAPPING ALPINE for ARMv7
echo "Bootstrapping Alpine for ARMv7"
qemu-arm-static /tmp/sbin/apk.static -X "$REPO/latest-stable/main" -U --allow-untrusted --root "$MNT" --initdb add alpine-base

# COMPLETE IMAGE MOUNTING FOR CHROOT
mount --bind /dev "$MNT/dev"
mount -t proc none "$MNT/proc"
mount --bind /sys "$MNT/sys"
mount --bind /dev/pts "$MNT/dev/pts"

# CONFIGURE ALPINE
cp /etc/resolv.conf "$MNT/etc/resolv.conf"
mkdir -p "$MNT/etc/apk"
cat > "$MNT/etc/apk/repositories" << REPOS
$REPO/latest-stable/main/
$REPO/latest-stable/community/
REPOS

# Create GUI startup script
echo "$STARTGUI" > "$MNT/startgui.sh"
chmod +x "$MNT/startgui.sh"

# CHROOT into ARM environment
echo "Chrooting into Alpine ARM environment"
cp "$(which qemu-arm-static)" "$MNT/usr/bin/"
chroot "$MNT" qemu-arm-static /bin/sh -c "$ALPINESETUP"
rm "$MNT/usr/bin/qemu-arm-static"

# UNMOUNT IMAGE & CLEANUP
echo "Unmounting image"
sync

# Unmount in reverse order
umount "$MNT/dev/pts" 2>/dev/null || true
umount "$MNT/sys" 2>/dev/null || true
umount "$MNT/proc" 2>/dev/null || true
umount -lf "$MNT/dev" 2>/dev/null || true

# Retry main unmount
for i in {1..5}; do
    umount "$MNT" 2>/dev/null && break
    echo "Retrying unmount ($i/5)..."
    sleep 2
done

if mountpoint -q "$MNT"; then
    echo "Warning: Could not unmount $MNT - trying lazy unmount"
    umount -l "$MNT" 2>/dev/null || true
fi

echo "Cleaning up"
rm -f /tmp/apk-tools-static.apk
rm -rf /tmp/sbin

echo "Image created at: $IMAGE"