#!/bin/bash

# Обновление системы
echo "🔄 Updating system..."
sudo pacman -Syu --noconfirm

# Установка rEFInd
echo "🧭 Installing rEFInd..."
sudo pacman -S refind --noconfirm
sudo refind-install

# Установка полезных утилит
echo "📦 Installing basic utilities..."
sudo pacman -S --noconfirm \
    git curl wget neofetch htop btop nano \
    networkmanager network-manager-applet \
    ntfs-3g exfatprogs fuse-exfat \
    pipewire pipewire-pulse wireplumber pavucontrol \
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
    polkit-gnome

# Включаем сетевой менеджер
echo "🌐 Enabling NetworkManager..."
sudo systemctl enable NetworkManager

# Настройка fstab для общего раздела (пример: /dev/sda7)
# echo "📝 Adding shared partition to /etc/fstab..."
# echo '/dev/sda7 /mnt/shared auto defaults,noatime 0 0' | sudo tee -a /etc/fstab

# Финализация
echo "✅ Done. Please reboot."
