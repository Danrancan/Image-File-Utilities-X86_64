#!/bin/bash
# install.sh — Image-File-Utilities-X86_64
# Installs all scripts to /usr/local/bin and verifies required packages.
# https://github.com/Danrancan/Image-File-Utilities-X86_64

set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash install.sh"
  exit 1
fi

SCRIPTS=(image-backup image-check image-chroot image-compare image-info image-mount image-shrink)
DEST="/usr/local/bin"

echo ""
echo "======================================================"
echo " Image-File-Utilities-X86_64 — Installer"
echo "======================================================"
echo ""
echo "Installing scripts to ${DEST}..."
echo ""

for SCRIPT in "${SCRIPTS[@]}"; do
  if [ -f "./${SCRIPT}" ]; then
    install -m 755 "./${SCRIPT}" "${DEST}/${SCRIPT}"
    echo "  ✔  ${SCRIPT}"
  else
    echo "  ✘  ${SCRIPT} NOT FOUND in current directory — skipping"
  fi
done

echo ""
echo "Checking required packages..."
echo ""

# Core packages — always required
CORE_DEPS=(rsync gdisk dosfstools e2fsprogs grub-efi-amd64 util-linux parted)

# Encryption packages — required for LUKS+LVM systems
LUKS_DEPS=(cryptsetup lvm2)

MISSING_CORE=()
MISSING_LUKS=()

for PKG in "${CORE_DEPS[@]}"; do
  dpkg -s "${PKG}" &> /dev/null || MISSING_CORE+=("${PKG}")
done
for PKG in "${LUKS_DEPS[@]}"; do
  dpkg -s "${PKG}" &> /dev/null || MISSING_LUKS+=("${PKG}")
done

if [ "${#MISSING_CORE[@]}" -ne 0 ]; then
  echo "Required packages not installed: ${MISSING_CORE[*]}"
  echo -n "Install them now (y/n)? "
  while read -r -n 1 -s a; do
    if [[ "${a}" = [yYnN] ]]; then
      echo "${a}"
      if [[ "${a}" = [yY] ]]; then break; else echo ""; echo "Install them manually and re-run."; exit 1; fi
    fi
  done
  echo ""
  apt-get update -qq
  apt-get install -y "${MISSING_CORE[@]}"
else
  echo "  ✔  Core packages satisfied."
fi

if [ "${#MISSING_LUKS[@]}" -ne 0 ]; then
  echo ""
  echo "LUKS/LVM packages not installed: ${MISSING_LUKS[*]}"
  echo "These are required only if your root filesystem is LUKS-encrypted."
  echo -n "Install them now (recommended) (y/n)? "
  while read -r -n 1 -s a; do
    if [[ "${a}" = [yYnN] ]]; then
      echo "${a}"
      if [[ "${a}" = [yY] ]]; then
        echo ""
        apt-get update -qq
        apt-get install -y "${MISSING_LUKS[@]}"
        break
      else
        echo "  (Skipped — install manually with: apt-get install ${MISSING_LUKS[*]})"
        break
      fi
    fi
  done
else
  echo "  ✔  LUKS/LVM packages satisfied."
fi

echo ""
echo "Ensuring ${DEST} is in PATH..."
if ! echo "${PATH}" | grep -q "${DEST}"; then
  echo "  Add this to your shell profile (~/.bashrc or /etc/environment):"
  echo "    export PATH=\$PATH:${DEST}"
fi

echo ""
echo "======================================================"
echo " Installation complete!"
echo "======================================================"
echo ""
echo "Test with:"
echo "  sudo image-backup -u --initial /mnt/RpiBackups/UbuntuCloneBackup.img"
echo ""
echo "For LUKS-encrypted systems:"
echo "  sudo image-backup --initial /mnt/RpiBackups/UbuntuCloneBackup.img"
echo "  (You will be prompted for the image LUKS passphrase)"
echo ""
