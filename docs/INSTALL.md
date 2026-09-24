# Установка: разметка → Windows → Arch

Схема и обоснования: `CONTEXT.md` (раздел 3) и `DECISIONS.md`. Этот файл — только порядок действий.
Команды рассчитаны на полную переразметку (Q1, подтверждено).

> ⚠️ Шаг 2 **уничтожает всё на диске**. До него должен быть готов и проверен бэкап C: и D:.

Итоговая раскладка (номера разделов не по порядку: Windows создаст свои разделы последними, это нормально, везде используем UUID):

```
nvme0n1p1   1 ГиБ    FAT32   ESP (общий)        → /boot в Arch
nvme0n1p4   16 МиБ   —       MSR                 (создаст Windows)
nvme0n1p5  ~250 ГиБ  NTFS    Windows C:          (создаст Windows)
nvme0n1p6  ~1 ГиБ    NTFS    Recovery            (создаст Windows)
nvme0n1p2   350 ГиБ  BTRFS   Arch
nvme0n1p3   250 ГиБ  NTFS    Share               → /mnt/share
           ~100 ГиБ  —       запас, не размечено
```

---

## 0. Подготовка в текущей Windows

1. Бэкап C: и D: на внешний диск или в облако. Отдельно проверить, что бэкап открывается.
2. Выписать ключи и лицензии: Windows (обычно в UEFI, переустановка подхватит сама), Ableton, FL Studio, Guitar Rig и остальное.
3. Флешка Ventoy с двумя образами: Arch ISO (свежий) и Windows 11 ISO.
4. BIOS (F2 при включении): режим UEFI, **Secure Boot → Disabled**. Меню загрузки — F12.

## 1. Live-USB Arch: проверка железа (ничего не пишем на диск)

```bash
setfont ter-132b                        # крупный шрифт для экрана 3000x2000
cat /sys/firmware/efi/fw_platform_size  # должно быть 64 — значит загрузились в UEFI
iwctl station wlan0 connect "ИМЯ_СЕТИ"  # WiFi
ping -c 3 archlinux.org
lsblk -f                                # посмотреть текущие разделы
```
Проверить тачпад (курсор в TTY не появится, это нормально, проверяем уже в Hyprland), звук (`speaker-test -c 2`), внешний монитор по USB-C.

## 2. Разметка диска (ДЕСТРУКТИВНО)

```bash
DISK=/dev/nvme0n1
lsblk $DISK                              # убедиться, что это тот самый 1 ТБ TOSHIBA

sgdisk --zap-all $DISK                   # стереть таблицу разделов целиком

# ESP 1 ГиБ в начале диска
sgdisk -n 1:0:+1G     -t 1:ef00 -c 1:EFI   $DISK
# Arch 350 ГиБ: начинается с отметки 253 ГиБ. Промежуток 1–253 ГиБ оставляем пустым под Windows
sgdisk -n 2:253G:+350G -t 2:8304 -c 2:Arch  $DISK
# Share 250 ГиБ сразу за Arch
sgdisk -n 3:603G:+250G -t 3:0700 -c 3:Share $DISK

sgdisk -p $DISK                          # проверить: p1 ~1G, p2 350G, p3 250G, до p2 ~252G пусто, в конце ~100G пусто
mkfs.fat -F 32 -n EFI ${DISK}p1          # отформатировать ESP
```
Share не форматируем: это сделает Windows (шаг 3), так NTFS получится «родной».

Выключить: `poweroff`.

## 3. Установка Windows

1. Загрузиться с флешки в установщик Windows 11.
2. На экране выбора диска выбрать **неразмеченное пространство ~252 ГиБ** и нажать «Далее».
   Установщик сам создаст там MSR, C: и Recovery, а загрузчик положит в наш ESP. Раздел Arch и Share **не трогать**.
3. После установки, в PowerShell от администратора:
   ```powershell
   manage-bde -status                 # если шифрование C: включено:
   manage-bde -off C:                 # выключить BitLocker (иначе после Arch Windows может запросить ключ восстановления)
   powercfg /h off                    # выключить гибернацию и Fast Startup — иначе Linux не сможет писать в NTFS
   # аппаратные часы в UTC, как у Linux (иначе время в Windows сдвигается на 3 часа)
   reg add "HKLM\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f
   ```
4. «Управление дисками» → раздел 250 ГиБ → Форматировать: NTFS, метка `Share`, назначить букву (например S:).
5. Проверить, что Windows нормально загружается.

## 4. Установка Arch

Снова загрузиться с Arch ISO, выполнить `setfont ter-132b` и подключить WiFi (как в шаге 1).

```bash
DISK=/dev/nvme0n1
ESP=${DISK}p1
ROOT=${DISK}p2
lsblk -f $DISK            # убедиться: p1 = vfat EFI (внутри уже есть Microsoft), p2 = 350G без ФС
```

> ⚠️ ESP **не форматировать**: на нём уже лежит загрузчик Windows.

### 4.1 BTRFS и subvolumes
```bash
mkfs.btrfs -L arch $ROOT
mount $ROOT /mnt
for sv in @ @home @snapshots @var_log @var_cache @swap; do btrfs subvolume create /mnt/$sv; done
umount /mnt

OPTS=compress=zstd,noatime
mount -o $OPTS,subvol=@          $ROOT /mnt
mount --mkdir -o $OPTS,subvol=@home      $ROOT /mnt/home
mount --mkdir -o $OPTS,subvol=@snapshots $ROOT /mnt/.snapshots
mount --mkdir -o $OPTS,subvol=@var_log   $ROOT /mnt/var/log
mount --mkdir -o $OPTS,subvol=@var_cache $ROOT /mnt/var/cache
mount --mkdir -o noatime,subvol=@swap  $ROOT /mnt/swap
mount --mkdir $ESP /mnt/boot

# Своп-файл 20 ГиБ под гибернацию (больше RAM с запасом). Лежит в своём subvolume, чтобы не попадать в снапшоты
btrfs filesystem mkswapfile --size 20g --uuid clear /mnt/swap/swapfile
```

### 4.2 Базовые пакеты
```bash
pacstrap -K /mnt base linux linux-firmware intel-ucode sof-firmware \
    btrfs-progs networkmanager sudo nano git man-db terminus-font zram-generator

genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's/,subvolid=[0-9]*//' /mnt/etc/fstab   # монтировать по имени subvolume, а не по id, чтобы работал откат снапшотов
echo '/swap/swapfile  none  swap  defaults,pri=10  0 0' >> /mnt/etc/fstab   # pri ниже, чем у zram: диск используется, только когда zram кончился
cat /mnt/etc/fstab                              # проверить: 6 строк btrfs + /boot vfat + swap
```

### 4.3 Настройка внутри системы
```bash
arch-chroot /mnt

ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/; s/^#ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
locale-gen
# Системный язык английский: так ошибки легко гуглить. Русский формат даты и чисел
printf 'LANG=en_US.UTF-8\nLC_TIME=ru_RU.UTF-8\nLC_NUMERIC=ru_RU.UTF-8\n' > /etc/locale.conf
printf 'KEYMAP=us\nFONT=ter-132b\n' > /etc/vconsole.conf

echo matebook > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 matebook\n' > /etc/hosts

# быстрый своп в сжатой RAM; своп-файл на диске нужен в основном для гибернации
printf '[zram0]\nzram-size = ram / 2\ncompression-algorithm = zstd\n' > /etc/systemd/zram-generator.conf

mkinitcpio -P

passwd                                    # пароль root
useradd -m -G wheel -s /bin/bash ИМЯ      # свой логин
passwd ИМЯ
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel

systemctl enable NetworkManager fstrim.timer systemd-boot-update.service

# Закрыл крышку → сон; через 3 часа сна → гибернация (всё сохраняется на диск, батарея не тратится)
mkdir -p /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d
printf '[Sleep]\nHibernateDelaySec=3h\n' > /etc/systemd/sleep.conf.d/hibernate.conf
printf '[Login]\nHandleLidSwitch=suspend-then-hibernate\n' > /etc/systemd/logind.conf.d/lid.conf
```

### 4.4 systemd-boot
```bash
bootctl install

cat > /boot/loader/loader.conf <<'EOF'
default arch.conf
timeout 5
console-mode max
editor no
EOF

ROOT_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)
# Где физически лежит своп-файл: ядру это нужно, чтобы при включении найти образ гибернации
RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r /swap/swapfile)
for kind in "" "-fallback"; do
cat > /boot/loader/entries/arch${kind}.conf <<EOF
title   Arch Linux${kind}
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux${kind}.img
options root=UUID=${ROOT_UUID} rootflags=subvol=@ rw resume=UUID=${ROOT_UUID} resume_offset=${RESUME_OFFSET}
EOF
done

bootctl list      # должны быть видны Arch Linux, Arch Linux-fallback и Windows Boot Manager
exit
umount -R /mnt
reboot
```

## 5. Первая загрузка

```bash
nmcli device wifi connect "ИМЯ_СЕТИ" password "ПАРОЛЬ"
sudo btrfs subvolume snapshot -r / /.snapshots/000-fresh-install    # точка отката «чистая система»
```
Проверить, что из меню systemd-boot загружается Windows, а из Windows удаётся перезагрузиться обратно в Arch.

### Проверка гибернации
```bash
swapon --show            # должны быть /dev/zram0 и /swap/swapfile
systemctl hibernate      # открыть пару окон/файлов, ноутбук выключится; включить → всё на месте
```
Если после включения система загрузилась «с нуля»: сверить `resume_offset` в `/boot/loader/entries/arch.conf`
с выводом `sudo btrfs inspect-internal map-swapfile -r /swap/swapfile`.

### Share
```bash
sudo mkdir -p /mnt/share
SHARE_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p3)
echo "UUID=${SHARE_UUID}  /mnt/share  ntfs3  uid=1000,gid=1000,umask=022,windows_names,noatime,nofail  0 0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /mnt/share
touch /mnt/share/test && rm /mnt/share/test    # проверить запись
```
Если монтируется только на чтение: в Windows не выключен Fast Startup (шаг 3.3).

Дальше: драйверы и envycontrol, потом Hyprland (фазы 2–3 из навыка `arch-hyprland-setup`).

---

## Приложение: Claude Code в live-среде (по желанию)

В live-ISO место под изменения ограничено оперативной памятью, по умолчанию около 256 МБ. Сначала расширить:
```bash
mount -o remount,size=4G /run/archiso/cowspace
pacman -Sy --noconfirm git
curl -fsSL https://claude.ai/install.sh | bash
git clone https://github.com/JoyRacon/ArchTry && cd ArchTry && ~/.local/bin/claude
```
Вход: Claude покажет ссылку, её открываем на телефоне, код вставляем обратно в терминал. Всё это исчезнет при перезагрузке.
Пока нет установленной системы, надёжнее держать открытым claude.ai/code на телефоне.
