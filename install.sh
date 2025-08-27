#!/bin/bash
set -e

DISK="/dev/nvme0n1p4"     # Partición para Linux (cifrada con LUKS)
CRYPT_NAME="main"         # Nombre para mapper LUKS

echo "=== CIFRADO LUKS ==="
if ! lsblk | grep -q "$CRYPT_NAME"; then
    if ! cryptsetup isLuks $DISK; then
        echo "Formateando con LUKS..."
        cryptsetup --batch-mode luksFormat $DISK
    else
        echo "El disco ya está en LUKS, abriéndolo..."
    fi
    cryptsetup luksOpen $DISK $CRYPT_NAME || true
else
    echo "$CRYPT_NAME ya está abierto."
fi

echo "=== FORMATEO BTRFS ==="
if ! blkid | grep -q "mapper/$CRYPT_NAME"; then
    echo "Formateando como BTRFS..."
    mkfs.btrfs /dev/mapper/$CRYPT_NAME
fi

echo "=== MONTAJE ROOT ==="
mkdir -p /mnt
if ! mount | grep -q "/mnt "; then
    mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async /dev/mapper/$CRYPT_NAME /mnt
fi
mkdir -p /mnt/boot

echo "=== SELECCIONAR PARTICIÓN EFI ==="
lsblk -f
read -p "Ingresa la partición EFI (ej: /dev/nvme0n1p1): " EFI_PART

echo "=== MONTANDO EFI ==="
if ! mount | grep -q "/mnt/boot "; then
    mount $EFI_PART /mnt/boot
fi

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
reflector -c Argentina,Brazil,Chile -a 12 --sort rate --save /etc/pacman.d/mirrorlist || true

echo "=== INSTALANDO SISTEMA BASE ==="
pacstrap -K /mnt base base-devel linux-zen linux-zen-headers linux-firmware \
    nano vim git man intel-ucode btrfs-progs ntfs-3g networkmanager openssh \
    grub efibootmgr grub-btrfs pipewire pipewire-alsa pipewire-pulse \
    pipewire-jack wireplumber reflector zsh zsh-completions \
    zsh-autosuggestions sudo || true

echo "=== GENERANDO FSTAB ==="
genfstab -U /mnt > /mnt/etc/fstab

echo "=== CHROOT AL NUEVO SISTEMA ==="
arch-chroot /mnt /bin/bash <<EOF
set -e
ln -sf /usr/share/zoneinfo/America/Argentina/Buenos_Aires /etc/localtime
hwclock --systohc

# Locale
grep -q "es_AR.UTF-8 UTF-8" /etc/locale.gen || echo "es_AR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=es_AR.UTF-8" > /etc/locale.conf

# Keymap
echo "KEYMAP=es" > /etc/vconsole.conf

# mkinitcpio para linux-zen
mkinitcpio -P linux-zen || true
EOF

echo "=== LISTO ==="

