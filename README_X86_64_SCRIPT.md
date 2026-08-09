# Image-File-Utilities-X86_64

**Bootable `.img` backup solution for live Ubuntu 24.04 / Debian 13 x86_64 servers.**

A full adaptation of [RonR's Image File Utilities](https://forums.raspberrypi.com/viewtopic.php?t=332000) (originally for Raspberry Pi), ported to x86_64 with support for:

- **UEFI-only boot** (GPT + EFI System Partition — no legacy BIOS mode)
- **Secure Boot** (installs `shim-signed` + signed GRUB when available)
- **Unencrypted ext4** root partitions
- **LUKS-encrypted LVM ext4** root partitions (Ubuntu/Debian default encrypted layout)
- **Automatic root filesystem shrink** to minimum size after every initial backup
- **Incremental rsync updates** to existing `.img` files

---

## What changed from the Raspberry Pi original

| Aspect | RPi Original | This x86_64 Port |
|---|---|---|
| Partition table | MBR (dos) | GPT always |
| Boot mode | BIOS / u-boot | UEFI only |
| Boot partition | FAT32 `/boot` 256 MB | FAT32 EFI System Partition 512 MB |
| `/boot` partition | (baked into root) | Separate ext4 1 GB when present or encrypted |
| Bootloader | u-boot + cmdline.txt | GRUB EFI + optional Secure Boot shim |
| Encrypted root | Not supported | LUKS2 + LVM — full clone with matching encryption |
| fstab references | PARTUUID= | UUID= (GPT+GRUB stable) |
| Resize on restore | SysV `update-rc.d` | systemd one-shot service |
| Output path restriction | `/mnt/` or `/media/` only | Any absolute path |

---

## Scripts

| Script | Purpose |
|---|---|
| `image-backup`  | **Main script.** Full or incremental backup of live system to `.img` |
| `image-check`   | Check filesystem integrity of a `.img` file |
| `image-chroot`  | chroot into a `.img` for inspection or repair |
| `image-compare` | Dry-run rsync diff: live system vs `.img` backup |
| `image-info`    | Show partition layout, UUIDs, LUKS info, GRUB config |
| `image-mount`   | Mount a single partition from a `.img` at a mountpoint |
| `image-shrink`  | Shrink root partition of a `.img` to minimum size |

---

## Installation

```bash
git clone https://github.com/Danrancan/Image-File-Utilities-X86_64.git
cd Image-File-Utilities-X86_64
sudo bash install.sh
```

`install.sh` copies scripts to `/usr/local/bin/`, sets permissions, and installs all required packages including `cryptsetup` and `lvm2` for encrypted system support.

---

## Requirements

- Ubuntu 24.04 or Debian 13 (x86_64)
- Root / sudo access
- Packages: `rsync gdisk dosfstools e2fsprogs grub-efi-amd64 util-linux`
- For LUKS systems: `cryptsetup lvm2`
- Destination with enough free space (≥ used disk space on root)

---

## Quick start

### Full initial backup (non-interactive)

```bash
# Unencrypted system
sudo image-backup -u --initial /mnt/RpiBackups/UbuntuCloneBackup.img

# Encrypted system (will prompt for image LUKS passphrase)
sudo image-backup --initial /mnt/RpiBackups/UbuntuCloneBackup.img

# Encrypted system — passphrase via flag (for scripted use)
sudo image-backup -p "your-passphrase" --initial /mnt/Backups/server-backup.img
```

### Incremental update of existing backup

```bash
sudo image-backup /mnt/RpiBackups/UbuntuCloneBackup.img
```

### Scheduled daily + monthly backups (crontab example)

```cron
# Daily incremental at 02:00
0 2 * * * root /usr/local/bin/image-backup /mnt/Backups/daily-$(date +\%A).img >> /var/log/image-backup.log 2>&1

# Full monthly backup on 1st at 03:00
0 3 1 * * root /usr/local/bin/image-backup -u --initial /mnt/Backups/monthly-$(date +\%Y-\%m).img >> /var/log/image-backup.log 2>&1
```

---

## Partition layouts

### Unencrypted — 2-partition

```
p1   512 MB   FAT32   EFI System Partition   (/boot/efi)
p2   variable ext4    Root filesystem        (/)
```

### Unencrypted — 3-partition (systems with separate /boot)

```
p1   512 MB   FAT32   EFI System Partition   (/boot/efi)
p2   1024 MB  ext4    Boot filesystem        (/boot)
p3   variable ext4    Root filesystem        (/)
```

### LUKS+LVM — 3-partition (encrypted — Ubuntu/Debian default)

```
p1   512 MB          FAT32        EFI System Partition   (/boot/efi)
p2   1024 MB         ext4         Boot filesystem        (/boot) [unencrypted]
p3   variable        crypto_LUKS  LUKS2 container
  └─ mapper/imgcrypt*  LVM2_member  Physical Volume
    └─ VG/LV           ext4         Root filesystem      (/)
```

The `/boot` partition **must remain unencrypted** on LUKS systems so GRUB can read the kernel and initrd before unlocking the LUKS container. This matches the layout used by Ubuntu 24.04 and Debian 13 encrypted installs.

The script **auto-detects** which layout applies by reading `/etc/fstab` and the device tree.

---

## LUKS encryption — how it works

When the live system has a LUKS-encrypted root:

1. A fresh **LUKS2 container** is created inside the image (`p3`) using a passphrase you supply
2. An **LVM physical volume, volume group, and logical volume** are created inside the LUKS container (matching the VG/LV names of the live system)
3. The LV is formatted **ext4** and the live system is **rsync'd** into it
4. `/etc/crypttab` inside the image is updated with the **new LUKS UUID**
5. `/etc/fstab` inside the image is updated to reference the **new LV mapper path**
6. **initramfs is rebuilt** inside a chroot so it includes `cryptsetup` and `lvm2` modules
7. **GRUB is configured** with `cryptdevice=UUID=<luks-uuid>:<mapper>` and `GRUB_ENABLE_CRYPTODISK=y`
8. A **first-boot systemd service** expands the LV and filesystem to fill the destination disk on restore

The image uses its **own** LUKS passphrase (not the live system's passphrase). The live system is never decrypted or modified.

---

## Secure Boot

On initial backup, the script attempts to install `shim-signed` inside the image chroot:

- **If `shim-signed` is already installed** on the live system (it will be in the image after rsync), the shim EFI binary is placed at the `--removable` UEFI boot path (`EFI/BOOT/BOOTX64.EFI`) where it chain-loads the signed `grubx64.efi`
- **If `shim-signed` is not available**, unsigned GRUB EFI is installed and a warning is printed

To ensure Secure Boot works, the live system should have `shim-signed` installed:

```bash
sudo apt-get install shim-signed
# Then re-run image-backup to pick it up
```

---

## Restoring a backup

Write the `.img` to a disk:

```bash
# dd (classic — shows progress on newer versions)
sudo dd if=/mnt/Backups/UbuntuCloneBackup.img of=/dev/sdX bs=4M status=progress conv=fsync

# pv (dedicated progress bar)
sudo pv UbuntuCloneBackup.img | sudo dd of=/dev/sdX bs=4M conv=fsync

# Balena Etcher (GUI) — also works
```

On first boot after restore:
- The **`resize-root-fs` systemd service** runs once, expands the root partition (and LV if LUKS), resizes the filesystem, then removes itself
- For LUKS systems, you will be prompted for the **image LUKS passphrase** (the one you set during backup — not the live system's passphrase)

---

## Utility commands

```bash
# Check image integrity (all partitions)
sudo image-check /mnt/Backups/UbuntuCloneBackup.img
sudo image-check -p "passphrase" /mnt/Backups/encrypted-backup.img Linux

# Inspect image details
sudo image-info /mnt/Backups/UbuntuCloneBackup.img
sudo image-info -p "passphrase" /mnt/Backups/encrypted-backup.img

# Mount root partition for file access
sudo mkdir -p /mnt/imgroot
sudo image-mount /mnt/Backups/UbuntuCloneBackup.img /mnt/imgroot Linux
sudo image-mount -p "passphrase" /mnt/Backups/encrypted-backup.img /mnt/imgroot Linux

# Compare live system to backup
sudo image-compare /mnt/Backups/UbuntuCloneBackup.img
sudo image-compare -p "passphrase" /mnt/Backups/encrypted-backup.img

# Shrink image to minimum size (standalone — image-backup does this automatically)
sudo image-shrink /mnt/Backups/UbuntuCloneBackup.img
sudo image-shrink -p "passphrase" /mnt/Backups/encrypted-backup.img

# chroot into image for repairs
sudo image-chroot /mnt/Backups/UbuntuCloneBackup.img
sudo image-chroot -p "passphrase" /mnt/Backups/encrypted-backup.img
```

---

## Troubleshooting

**`losetup` fails / no loop devices**
```bash
modprobe loop
ls /dev/loop*
```

**GRUB install warning during backup**
Harmless in offline chroot. The EFI binaries are copied via rsync; `grub-install` only fails to update NVRAM (which is correct — the image must be device-agnostic).

**Image won't boot — manual GRUB re-install**
```bash
sudo losetup -Pf /path/to/backup.img
# For 3-part layout:
sudo mount /dev/loopXp3 /mnt
sudo mount /dev/loopXp2 /mnt/boot
sudo mount /dev/loopXp1 /mnt/boot/efi
# Bind mounts
for d in dev dev/pts sys proc run; do sudo mount --bind /${d} /mnt/${d}; done
sudo chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable
sudo chroot /mnt update-grub
for d in dev/pts dev sys proc run; do sudo umount /mnt/${d}; done
sudo umount /mnt/boot/efi /mnt/boot /mnt
sudo losetup -d /dev/loopX
```

**LUKS: wrong passphrase / can't open container**

The image LUKS passphrase is set during the initial backup — it is **independent** of the live system's passphrase. If you forgot it, you must create a new backup.

**`/mnt/RpiBackups/` does not exist**
```bash
sudo mkdir -p /mnt/RpiBackups
# Or point to your external drive's mount point
```

---

## Credits

- Original scripts: **RonR** — [Raspberry Pi Forums Image File Utilities thread](https://forums.raspberrypi.com/viewtopic.php?t=332000)
- RPi script mirror: [seamusdemora/RonR-RPi-image-utils](https://github.com/seamusdemora/RonR-RPi-image-utils)
- x86_64 adaptation: [Danrancan/Image-File-Utilities-X86_64](https://github.com/Danrancan/Image-File-Utilities-X86_64)

---

## License

GPL-3.0 — see [LICENSE](LICENSE)
