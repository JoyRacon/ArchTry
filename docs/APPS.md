# Приложения: что есть на Windows и что с ними будет

Источник: `scripts/windows/inventory.ps1`, прогон 2026-10-05 (85 программ, диски: C: 153.5 / 15.5 ГБ свободно, D: 32.7 / 67.3 ГБ).

> 🔒 Конфиги VPN, SSH-ключи, Tabby и пароли Wi-Fi — **только на внешнем диске**, никогда в этот репозиторий.

## Критичные: без них нет работы или нет Claude

| Программа | Зачем | Что сохранить до стирания | На Arch | Статус |
|---|---|---|---|---|
| **Throne 1.1.6** (портативный, `Downloads\Throne-1.1.6-windows64`) | VPN → доступ к Claude | `config` скопирован скриптом; дополнительно ссылки профилей (ПКМ → Share → Copy link) и **вся папка Throne** (Downloads будет стёрт) | Throne для Linux (релиз на GitHub / AUR) либо `sing-box` + JSON-конфиг | ⏳ ссылки |
| **WireGuard 1.1** | домашние серверы | Export tunnels to zip | `wireguard-tools`; `nmcli connection import type wireguard file wg0.conf` | ⏳ экспорт |
| **Tailscale 1.96** | проекты товарища | ничего: на Linux просто войти в тот же аккаунт | `tailscale` (репозиторий extra), `systemctl enable --now tailscaled && tailscale up` | ✅ |
| **Tabby 1.0.237** | SSH по работе | `config.yaml` скопирован скриптом; мастер-пароль vault, если включён | `tabby-bin` (AUR), `config.yaml` → `~/.config/tabby/` | ⏳ проверить vault |
| SSH-ключи (`.ssh`, 9 файлов) | серверы, git | скопированы скриптом | `~/.ssh`, `chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*` | ✅ |
| **Рабочий VPN** (встроенный VPN Windows) | работа | тип и адрес — в `secrets\windows-vpn.csv` (колонка `TunnelType`). **Пароль, общий ключ (PSK) и сертификаты Windows не экспортирует** — записать заранее или взять у админа | плагин NetworkManager под тип: L2TP → `networkmanager-l2tp`, IKEv2 → `networkmanager-strongswan`, SSTP → `networkmanager-sstp` (AUR), PPTP → `networkmanager-pptp` | ⏳ узнать тип и данные для входа |

## Доступ к Claude во время установки

Claude открывается только через VPN. Throne работает на ядре sing-box, поэтому те же серверы поднимаются
в консоли Linux без графики — уже в live-среде, сразу после подключения Wi-Fi.

### Подготовка на Windows (один раз)
1. Throne → выделить все профили → ПКМ → Share → Copy link → вставить в `links.txt` (по ссылке на строку;
   можно и ссылку подписки `https://...`). **Файл секретный** — не в git, не в чат.
2. Сделать конфиг (Python на Windows уже есть):
   ```powershell
   python scripts\vpn\links2singbox.py links.txt -o E:\iso\archtry\config.json
   ```
   Поддерживается: vless (tls / reality, tcp / ws / grpc / httpupgrade / h2), trojan, vmess, ss, hysteria2, tuic.
   Если серверов несколько — sing-box сам выберет самый быстрый (urltest).
   Не поддерживаются sing-box'ом: транспорт xhttp/splithttp и kcp — такие ссылки конвертер пропустит с пояснением.
3. В `E:\iso\archtry\` положить `scripts/vpn/vpn-live.sh`. Запасной `sing-box` для Linux туда же скачивает `get-isos.ps1`.
4. После Ventoy скопировать папку `archtry\` на флешку целиком.

### В live-Arch (после `iwctl ... connect`)
```bash
mount --mkdir -o ro /dev/disk/by-label/Ventoy /mnt/usb
cp -r /mnt/usb/archtry /root/ && umount /mnt/usb
bash /root/archtry/vpn-live.sh --claude     # VPN + проверка + установка Claude Code
source /tmp/vpn.env                          # прокси в этой консоли — обязательно
git clone https://github.com/JoyRacon/ArchTry && cd ArchTry && claude
```
Скрипт: ставит sing-box (из репозитория Arch, иначе с флешки), проверяет конфиг, запускает его как локальный прокси
`127.0.0.1:2080`, проверяет связь с `api.anthropic.com` **через VPN** и пишет страну выхода. Зеркала Arch идут напрямую.
Вход в Claude: Claude покажет ссылку → открыть на телефоне → код вставить в консоль.
Если VPN не поднялся — `tail -50 /tmp/sing-box.log`, а Claude пока с телефона.

### Дальше
- **На установленном Arch без графики:** тот же `vpn-live.sh` (лежит в `/root/archtry`, скопировать в систему до перезагрузки).
- **Постоянно:** `links2singbox.py --tun` → `/etc/sing-box/config.json` + `systemctl enable --now sing-box` — весь трафик через VPN.
- **После Hyprland:** Throne с графическим интерфейсом, как сейчас на Windows.
- После установки удалить `archtry\` с флешки: там ключи VPN.

## Данные: что бэкапить

Личных данных мало — весь бэкап без VM и игр уложится примерно в 30 ГБ.

| Где | Размер | Что делать |
|---|---|---|
| `C:\Users\Joyracon\Downloads` | 24 ГБ | разобрать: скорее всего установщики и ISO. Нужное — в бэкап, остальное не жалко |
| `D:\VMs` | 20 ГБ (5 файлов) | ✅ не нужны, не бэкапим |
| `D:\SteamLibrary` + игры на C: | ~7.5 ГБ | не бэкапить: Steam скачает заново, сохранения в Steam Cloud |
| `AppData\Local\wsl` | 3.9 ГБ | ✅ старые разработки, не бэкапим |
| `.lmstudio` + `D:\LM Studio` | 2.8 ГБ | модели можно скачать заново; бэкап — только если качать долго |
| `Pictures`, `Documents`, `Desktop` | ~2.7 ГБ | в бэкап целиком |
| `D:\Project's`, `D:\screenshots`, `D:\Nebula crt` | мелочь | в бэкап целиком |
| `D:\LoreForge`, `D:\command-hub`, `D:\lore-wiki`, `D:\JsNetWebTemplate-main` | мелочь | git-репозитории: проверить, что всё запушено (команда ниже), на Arch склонировать в `~/projects` |
| Anki (`Roaming\Anki2`) | 0.3 ГБ | синхронизировать с AnkiWeb или забэкапить папку |
| Telegram | 0.7 ГБ | ничего: всё в облаке |
| Obsidian | ? | ⏳ найти хранилища командой ниже; бэкапить папку хранилища целиком (вместе со скрытой `.obsidian`); после переустановки положить на Share в `obsidian\` (D9) |
| OneDrive | облако | ничего, локально почти пусто |

Проверка git-проектов, что ничего не потеряется (PowerShell):
```powershell
Get-ChildItem 'D:\', $env:USERPROFILE -Directory -Recurse -Depth 3 -Force -Filter .git -ErrorAction SilentlyContinue | ForEach-Object {
    $r = $_.Parent.FullName
    [pscustomobject]@{
        Repo     = $r
        Changed  = @(git -C $r status --porcelain).Count                      # незакоммиченные файлы
        Unpushed = @(git -C $r log --branches --not --remotes --oneline).Count # коммиты, которых нет на сервере
        Remote   = (git -C $r remote get-url origin 2>$null)
    }
} | Format-Table -AutoSize
```
Везде должно быть `Changed 0`, `Unpushed 0` и непустой `Remote`.

## Obsidian: найти хранилища и настройки

Список хранилищ Obsidian хранит в `%APPDATA%\obsidian\obsidian.json`. Плагины, темы, горячие клавиши и настройки каждого хранилища
лежат **внутри него**, в скрытой папке `.obsidian` — поэтому достаточно скопировать папку хранилища целиком.

```powershell
$cfg = Get-Content "$env:APPDATA\obsidian\obsidian.json" -Raw | ConvertFrom-Json
$cfg.vaults.PSObject.Properties | ForEach-Object {
    $p = $_.Value.path
    [pscustomobject]@{
        Vault   = $p
        SizeMB  = [math]::Round((Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
        Plugins = (Get-ChildItem -LiteralPath "$p\.obsidian\plugins" -Directory -ErrorAction SilentlyContinue).Name -join ', '
    }
} | Format-List
```
Если хранилище в OneDrive: сначала ПКМ по папке → «Всегда сохранять на этом устройстве», иначе часть файлов только в облаке.
Плюс скопировать `%APPDATA%\obsidian` (глобальные настройки приложения, мелочь).

## Лицензии и ключи (до переустановки Windows!)

- **Microsoft Office LTSC 2024 Pro Plus + Visio LTSC 2024**: нужен установщик и ключ/способ активации — без них после переустановки не вернуть.
- **FL Studio 2025**: вход в аккаунт Image-Line. **Guitar Rig 7**: Native Access, аккаунт NI.
- **Ableton Live 12** — сейчас Trial, лицензии нет.
- **AdGuard**: ключ лицензии в личном кабинете AdGuard.
- Windows: ключ обычно зашит в UEFI, переустановка активируется сама.

## Всё остальное: решение по каждой программе

**Остаются только на Windows:** Ableton Live 12, FL Studio 2025 (+ FL Cloud Plugins, ASIO), Guitar Rig 7, драйверы Focusrite и Ableton USB Audio,
Office LTSC + Visio, Huawei PC Manager и HW OSD, Logitech G HUB, NVIDIA App, Cheat Engine, игры Steam.
После переустановки Windows бóльшую часть ставим одной командой: `winget import -i winget.json` (файл из инвентаризации).

**Переезжают на Arch:**

| Программа | Пакет на Arch | Комментарий |
|---|---|---|
| VS Code + 9 расширений | `visual-studio-code-bin` (AUR) | расширения из `vscode-extensions.txt`; Remote-SSH и Claude Code работают |
| Git, Python, Pandoc, 7-Zip | `git python pandoc-cli 7zip` | |
| Obsidian | `obsidian` | хранилище на Share `/mnt/share/obsidian`, общее с Windows (D9) |
| Telegram | `telegram-desktop` | |
| Discord | `discord` | |
| Chrome | `google-chrome` (AUR) | или `chromium`; вход в аккаунт вернёт закладки и расширения |
| Postman | `postman-bin` (AUR) | |
| PuTTY, WinSCP | `openssh`, Tabby, `filezilla` | на Linux PuTTY не нужен |
| Anki | `anki-bin` (AUR) | |
| LM Studio | AppImage с сайта | |
| Creality Print 6.3 | AppImage с GitHub Creality | или `orca-slicer-bin` (AUR) |
| VirtualBox | `virtualbox` или `virt-manager` (QEMU/KVM) | на Linux KVM быстрее |
| Moonlight | `moonlight-qt-bin` (AUR) | |
| Noi | AppImage с GitHub | |
| Яндекс Музыка | веб-версия или `yandex-music` (AUR, неофициальный) | |
| BitTorrent Web | `qbittorrent` | |
| Dion (работа) | проверить Linux-сборку на сайте Dion (deb/rpm → на Arch через `debtap` или AUR), иначе веб-версия в браузере | ⏳ |
| Принтер Canon G3010 | `cups` + `cnijfilter2` (AUR) или драйвер без установки (IPP Everywhere) | |
| Мышь Logitech | `piper` (настройка кнопок/DPI) | G HUB на Linux нет |
| AdGuard | расширение в браузере (uBlock Origin / AdGuard) | |

**Не нужны на Linux:** eXpress, VirtualBox-машины из `D:\VMs`, WSL, balenaEtcher, Armbian Imager (`dd`/Impression), DiskInternals Linux Reader, Intel Driver Assistant, драйверы NVIDIA/Intel/Canon-утилиты Windows, Ruffle (есть в браузере).
