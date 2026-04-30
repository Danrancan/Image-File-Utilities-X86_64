# Image-File-Utilities-X86_64
Backup Solution for cloning a Live Debian or Ubuntu Server to a bootable ".img" file. Based off of the set of bash scripts called "Image File Utilities" (https://forums.raspberrypi.com/viewtopic.php?t=332000#p1511694) created by RonR (https://forums.raspberrypi.com/memberlist.php?mode=viewprofile&u=186692&sid=b8ad4e175a4d6ab7ca3652e03de8ad49) in the Raspberry Pi Forums (https://forums.raspberrypi.com/).

The original set of scripts can be downloaded from https://forums.raspberrypi.com/download/file.php?id=74592

These scripts should successfully clone your running Ubuntu/Debian OS to an "img" file on a specified external hard drive. To run them, move them to /usr/local/bin/script-goes-here, and then run `sudo chmod +x /usr/local/bin/script-goes-here` on each script.
Make sure `/user/local/bin/*` is in your `$PATH`.

Syntax to make a full initial backup:
```
/usr/local/bin/image-backup -u --initial /mnt/Backup-Drive/$(date +\%Y\-\%m\-\%d\_\%H\.\%M\.\%S)-IMAGE_UTILS-BACKUP.img
```

