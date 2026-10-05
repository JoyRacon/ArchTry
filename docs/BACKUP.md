# Бэкап Windows перед стиранием диска

Цель — двойная страховка на внешнем диске 2 ТБ:
1. **Образ системы** (C: и D: целиком, `.vhdx`). Если что-то забыли — подключаем образ как диск и достаём файл.
2. **Копия файлов** (профиль и D:). Обычные папки — открываются где угодно, в том числе из Arch.

Сейчас занято ≈ 190 ГБ (C: 153.5 + D: 32.7), образ + копия файлов ≈ 250–300 ГБ.

## 1. Сначала посмотреть, что за старый бэкап на внешнем диске

Не стирать вслепую — там могут быть старые фото или документы, которых больше нигде нет.
Подробный отчёт (формат бэкапа, типы файлов, годы, крупные папки): `scripts/windows/scan-drive.ps1 -Drive E`.
```powershell
# E: — буква внешнего диска, подставить свою
Get-Volume -DriveLetter E | Select-Object FileSystemType, Size, SizeRemaining
Get-ChildItem E:\ -Force | Select-Object Name, LastWriteTime
```
- Папка `WindowsImageBackup` — старый образ Windows: подключить `.vhdx` (см. шаг 4) и проверить, нет ли там нужного.
- Файлы `.tib` / `.mrimg` — Acronis / Macrium: открыть можно только их программами.
- Если нужное нашлось — скопировать в бэкап этого раза (папка `old-backup-rescued\`), потом стирать.

Файловая система диска должна быть **NTFS** (образ системы Windows на exFAT не пишется).
Если диск exFAT — переформатировать в NTFS **только после** проверки старого бэкапа: «Управление дисками» → ПКМ → Форматировать → NTFS.

## 2. Образ системы (C: и D:)

PowerShell от администратора:
```powershell
wbadmin start backup -backupTarget:E: -include:C:,D: -allCritical -quiet
```
Или мышкой: Панель управления → «Резервное копирование и восстановление (Windows 7)» → «Создание образа системы» → внешний диск → отметить C: и D:.
Займёт 1–2 часа. Результат: `E:\WindowsImageBackup\<имя ПК>\Backup <дата>\*.vhdx`.

> BitLocker: проверить `manage-bde -status`. wbadmin читает том через систему, поэтому образ, как правило, получается незашифрованным —
> это видно на шаге 5 (подключился и открылся без ключа). Ключ восстановления BitLocker в любом случае сохранить в `secrets`.

## 3. Копия файлов (обычные папки)

PowerShell от администратора. `robocopy` копирует с датами, пропускает заблокированные файлы и пишет лог.
```powershell
$dst = 'E:\matebook-2026-10'   # папка бэкапа на внешнем диске
$opt = '/E','/XJ','/COPY:DAT','/DCOPY:DAT','/R:1','/W:1','/MT:16','/NP'
# /XJ — не заходить в ссылки-«ярлыки» папок (иначе зацикливается на AppData)

# профиль пользователя без кэшей
robocopy $env:USERPROFILE "$dst\profile" @opt /XD Temp Cache 'Code Cache' GPUCache wsl /LOG:"$dst\robocopy-profile.log"

# диск D: без виртуалок и игр
robocopy D:\ "$dst\D" @opt /XD VMs SteamLibrary '$RECYCLE.BIN' 'System Volume Information' /LOG:"$dst\robocopy-D.log"
```
Коды выхода robocopy 0–7 — успех, 8 и выше — были ошибки. Проверить лог:
```powershell
Select-String -Path "$dst\robocopy-*.log" -Pattern 'ERROR|ОШИБКА' | Select-Object -First 30
```
Ошибки на `NTUSER.DAT`, `UsrClass.dat` и файлах в `AppData` запущенных программ — нормально (они заняты системой и есть в образе).

## 4. Секреты

Папку `secrets\` из инвентаризации (VPN, SSH, Tabby, Wi-Fi) + экспорт WireGuard + ссылки Throne + ключ BitLocker
положить на внешний диск **только в архиве с паролем**:
7-Zip → Добавить в архив → формат 7z, шифрование AES-256, ✔ «Шифровать имена файлов».
Пароль от архива записать не на этом диске.

## 5. Проверка — до стирания ноутбука!

1. Подключить образ: открыть `E:\WindowsImageBackup\...\Backup <дата>\`, ПКМ по большому `.vhdx` → «Подключить».
   Появится новый диск — открыть пару файлов из Documents и D:, затем ПКМ по диску → «Извлечь».
2. В `E:\matebook-2026-10\profile` и `\D` открыть несколько файлов: фото, документ, проект.
3. Открыть архив секретов паролем.

Только после трёх ✅ — к шагу 2 INSTALL.md (разметка).

## Достать файл позже из Arch

```bash
sudo pacman -S --needed qemu-img ntfs-3g
sudo modprobe nbd max_part=8
sudo qemu-nbd --read-only --format=vhdx --connect=/dev/nbd0 '/путь/к/Backup <дата>/<файл>.vhdx'
lsblk /dev/nbd0                      # найти раздел с данными, например nbd0p2
sudo mount -o ro /dev/nbd0p2 /mnt/img
# ... скопировать нужное ...
sudo umount /mnt/img && sudo qemu-nbd --disconnect /dev/nbd0
```
