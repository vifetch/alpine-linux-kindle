# Alpine Linux on Kindle
A project to bring modern Alpine Linux 32-bit to Kindle devices (with a focus on compatibility for the Paperwhite 5, but many others may work) with support for the latest branch

# Screenshots (WIP)

# Installation
1. Have a jailbroken Kindle, with KAUL + Kterm installed (be aware if your Kindle uses hard floats that you will need Kterm for ARMHF or else Alpine's menu, as well as Kterm will not launch)
2. Download copy_to_extensions/alpine_kindle_kual and place in the extensions folder on Kindle
3. From KUAL, open the Alpine Linux menu and deploy the latest release, it will download from the latest stable included in this repo

Afterwards, you are able to launch Alpine directly from KAUL

- To disable the Kindle framework when running Alpine (frees more ram) run the following in Kterm:
```
mntroot rw
cp /mnt/us/alpine.conf /etc/upstart/
mntroot r
```

# Building
To build your own Alpine release, you must have the following:
- (Relatively) modern Linux kernel (alternatively, WSL also works)
- qemu-user-static (qemu-armhf-static / qemu-armv7-static)

1. Download buildtools/
2. Start by running create_kindle_alpine_image.sh to create your alpine.ext3 file. This is the filesystem your Kindle is chrooting into. (Note: Many build issues in this stage are a result of your required qemu environment!)
3. After being dropped into the chroot shell, currently you must add any packages you may want (xournal++, fastfetch, lynx, etc) but notably you must run setup-desktop in order to have a working DE. Once you have everything you'd like installed to your filesystem, you can exit
4. Run create_release.sh to bundle the filesystem along with alpine.conf and alpine.sh

# Why?
Initially, I wanted a Kindle Scribe type of device. Already having a Kindle Paperwhite Gen 5 (Kindle 11th Gen) and some basic knowledge that all Kindles used Linux under the hood from past jailbreaking, I went on to figure out what my best option would be to turn my existing device into a basic handwritten note keeper, with the ability to export my drawings. 

Finding the amazing work several years ago from [schuhumi](https://github.com/schuhumi), I found I could run Alpine Linux on almost any Kindle, _however_ the releases included had not been updated in years, and caused me to run into several issues when running simple commands, like apk (seg faults, signature issues, and other unexplainable issues I experienced when chrooting into the env with packages over half a decade old). I decided to create new builds myself and make this repo for anyone who might benefit from a newer Alpine release.

# Credits
using code from: [schuhumi/alpine_kindle](https://github.com/schuhumi/alpine_kindle) & [schuhumi/alpine_kindle_kauh](https://github.com/schuhumi/alpine_kindle_kual)

# Troubleshooting
- If you are unable to load into Alpine *except* through a shell, ensure your DE is installed (run setup-desktop through Kterm then run Alpine again from KAUL). You can also run `./startgui.sh` from the chroot shell (Drop into Alpine Linux shell)
- When logging out of the chrooted environment through X11, you may be brought to a blank screen forever. Simply hold the power button on your Kindle for about 10 seconds and it should reboot back to the Kindle framework without any lasting issues.
- The terminal is *probably* not broken, you just currently need to adjust the colors as the contrast of the Kindle cannot show the default color profile.

# TODO
- Replace zip compression with tarball (alternatively, zerofree?)
- Include version testing within KAUL
- Auto set high-contrast theme, white background
- Fix terminal visibility
- Add patch to enable keyboard on lock screen
