#!/bin/bash
set -e

DISK="/dev/nvme0n1"          # Disco donde está tu instalación de Linux
CRYPT_NAME="main"             # Nombre del mapper LUKS

echo "=== CIFRADO LUKS ==="
cryptsetup --batch-mode luksFormat ${DISK}p2
cryptsetup luksOpen ${DISK}p2 $CRYPT_NAME

echo "=== FORMATEO BTRFS ==="
mkfs.btrfs /dev/mapper/$CRYPT_NAME

echo "=== MONTANDO BTRFS ==="
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async /dev/mapper/$CRYPT_NAME /mnt

echo "=== SELECCIONA LA PARTICIÓN EFI ==="
lsblk -f
read -p "Ingresa la partición EFI (ej: /dev/nvme0n1p1): " EFI_PART

echo "=== LIMPIANDO EFI (solo Linux, conservando Windows) ==="
mkdir -p /mnt/efi_temp
mount $EFI_PART /mnt/efi_temp

for dir in /mnt/efi_temp/EFI/*; do
    basename=$(basename "$dir")
    if [[ "$basename" != "Microsoft" ]]; then
        echo "Borrando $dir"
        rm -rf "$dir"
    else
        echo "Conservando $dir"
    fi
done

umount /mnt/efi_temp

mkdir -p /mnt/boot
mount $EFI_PART /mnt/boot

echo "=== ACTUALIZANDO MIRRORLIST ==="
reflector -c Argentina -c Brazil -c Chile -a 12 --sort rate --save /etc/pacman.d/mirrorlist

echo "=== INSTALANDO BASE Y PAQUETES ==="
pacstrap /mnt base base-devel linux-zen linux-zen-headers linux-firmware \
    nano vim git man intel-ucode btrfs-progs ntfs-3g networkmanager \
    openssh grub efibootmgr grub-btrfs pipewire pipewire-alsa \
    pipewire-pulse pipewire-jack wireplumber reflector \
    zsh zsh-completions zsh-autosuggestions sudo

echo "=== GENERANDO FSTAB ==="
genfstab -U /mnt >> /mnt/etc/fstab

echo "=== CONFIGURACIÓN DENTRO DEL CHROOT ==="
arch-chroot /mnt /bin/bash <<EOF
# Zona horaria
ln -sf /usr/share/zoneinfo/America/Argentina/Buenos_Aires /etc/localtime
hwclock --systohc

# Locales en español
echo "es_ES.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=es_ES.UTF-8" > /etc/locale.conf

# Teclado en consola
echo "KEYMAP=es" > /etc/vconsole.conf

# Hostname
echo "archlinux" > /etc/hostname

# Generar initramfs para kernel zen
mkinitcpio -P -k linux-zen
EOF

echo "=== INSTALACIÓN COMPLETA ==="
echo "Recordá instalar GRUB con soporte LUKS y BTRFS después:"
echo "arch-chroot /mnt"
echo "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"
echo "grub-mkconfig -o /boot/grub/grub.cfg"
