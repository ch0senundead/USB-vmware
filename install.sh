#!/bin/bash
set -e

DISK="/dev/nvme0n1p4"     # Partición para Linux (cifrada con LUKS)
CRYPT_NAME="main"         # Nombre para mapper LUKS

echo "=== CIFRADO LUKS ==="
cryptsetup --batch-mode luksFormat $DISK
cryptsetup luksOpen $DISK $CRYPT_NAME

echo "=== FORMATEO BTRFS ==="
mkfs.btrfs /dev/mapper/$CRYPT_NAME

echo "=== MONTAJE ROOT ==="
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async /dev/mapper/$CRYPT_NAME /mnt
mkdir -p /mnt/boot

echo "=== SELECCIONAR PARTICIÓN EFI ==="
lsblk -f
read -p "Ingresa la partición EFI (ej: /dev/nvme0n1p1): " EFI_PART

echo "=== MONTANDO EFI ==="
mount $EFI_PART /mnt/boot

echo "=== LIMPIEZA DE EFI (Linux viejo) ==="
for dir in /mnt/boot/EFI/*; do
    case "$(basename "$dir")" in
        "Microsoft"|"Boot")
            echo "Conservando $(basename "$dir")"
            ;;
        *)
            echo "Eliminando $(basename "$dir")"
            rm -rf "$dir"
            ;;
    esac
done

echo "=== GENERANDO MIRRORLIST ==="
reflector -c Argentina,Brazil,Chile -a 12 --sort rate --save /etc/pacman.d/mirrorlist

echo "=== INSTALANDO SISTEMA BASE ==="
pacstrap /mnt base base-devel linux-zen linux-zen-headers linux-firmware \
    nano vim git man intel-ucode btrfs-progs ntfs-3g networkmanager openssh \
    grub efibootmgr grub-btrfs pipewire pipewire-alsa pipewire-pulse \
    pipewire-jack wireplumber reflector zsh zsh-completions \
    zsh-autosuggestions sudo

echo "=== GENERANDO FSTAB ==="
genfstab -U /mnt >> /mnt/etc/fstab

echo "=== CHROOT AL NUEVO SISTEMA ==="
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/America/Argentina/Buenos_Aires /etc/localtime
hwclock --systohc

# Locale
echo "es_AR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=es_AR.UTF-8" > /etc/locale.conf

# Keymap
echo "KEYMAP=es" > /etc/vconsole.conf

# mkinitcpio para linux-zen
mkinitcpio -P linux-zen
EOF

echo "=== LISTO ==="

