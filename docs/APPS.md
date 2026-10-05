# Приложения: что есть на Windows и что с ними будет

Источник: `scripts/windows/inventory.ps1`, прогон 2026-10-05 (85 программ, диски: C: 153.5 / 15.5 ГБ свободно, D: 32.7 / 67.3 ГБ).

> 🔒 Конфиги VPN, SSH-ключи, Tabby и пароли Wi-Fi — **только на внешнем диске**, никогда в этот репозиторий.

## Критичные: без них нет работы или нет Claude

| Программа | Зачем | Что сохранить до стирания | На Arch | Статус |
|---|---|---|---|---|
| **Throne 1.1.6** (портативный, `Downloads\Throne-1.1.6-windows64`) | VPN → доступ к Claude | `config` скопирован скриптом; дополнительно ссылки профилей (ПКМ → Share → Copy link) и **вся папка Throne** (Downloads будет стёрт) | Throne для Linux (релиз на GitHub / AUR) либо `sing-box` + JSON-конфиг | ⏳ ссылки |
| **WireGuard 1.1** | работа | Export tunnels to zip | `wireguard-tools`; `nmcli connection import type wireguard file wg0.conf` | ⏳ экспорт |
| **Tailscale 1.96** | доступ к своей сети (VM, command-hub?) | ничего: на Linux просто войти в тот же аккаунт | `tailscale` (репозиторий extra), `systemctl enable --now tailscaled && tailscale up` | ✅ |
| **Tabby 1.0.237** | SSH по работе | `config.yaml` скопирован скриптом; мастер-пароль vault, если включён | `tabby-bin` (AUR), `config.yaml` → `~/.config/tabby/` | ⏳ проверить vault |
| SSH-ключи (`.ssh`, 9 файлов) | серверы, git | скопированы скриптом | `~/.ssh`, `chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*` | ✅ |
| Рабочий VPN | работа | — | — | ❓ Q5: это WireGuard или Tailscale? Других VPN-клиентов не найдено |

## Доступ к Claude во время установки

Claude открывается только через VPN, а на чистой системе VPN ещё нет. Поэтому:

1. **Live-USB и разметка:** Claude на телефоне (claude.ai/code через VPN на телефоне).
2. **Первая загрузка Arch, ещё без графики:** поднять `sing-box` из консоли по конфигу из Throne, затем Claude Code CLI.
   Готовый JSON для sing-box соберём заранее из ссылок профилей и проверим ещё в live-среде (INSTALL.md, шаг 1).
3. **После Hyprland:** Throne с графическим интерфейсом, как сейчас на Windows.

## Данные: что бэкапить

Личных данных мало — весь бэкап без VM и игр уложится примерно в 30 ГБ.

| Где | Размер | Что делать |
|---|---|---|
| `C:\Users\Joyracon\Downloads` | 24 ГБ | разобрать: скорее всего установщики и ISO. Нужное — в бэкап, остальное не жалко |
| `D:\VMs` | 20 ГБ (5 файлов) | ❓ что за виртуалки? Нужные — в бэкап (VirtualBox есть и на Linux) |
| `D:\SteamLibrary` + игры на C: | ~7.5 ГБ | не бэкапить: Steam скачает заново, сохранения в Steam Cloud |
| `AppData\Local\wsl` | 3.9 ГБ | ❓ есть WSL-дистрибутив. Если там что-то нужное: `wsl -l -v`, затем `wsl --export <имя> D:\wsl-backup.tar` |
| `.lmstudio` + `D:\LM Studio` | 2.8 ГБ | модели можно скачать заново; бэкап — только если качать долго |
| `Pictures`, `Documents`, `Desktop` | ~2.7 ГБ | в бэкап целиком |
| `D:\Project's`, `D:\screenshots`, `D:\Nebula crt` | мелочь | в бэкап целиком |
| `D:\LoreForge`, `D:\command-hub`, `D:\lore-wiki`, `D:\JsNetWebTemplate-main` | мелочь | git-репозитории: проверить, что всё запушено (команда ниже), на Arch склонировать в `~/projects` |
| Anki (`Roaming\Anki2`) | 0.3 ГБ | синхронизировать с AnkiWeb или забэкапить папку |
| Telegram | 0.7 ГБ | ничего: всё в облаке |
| Obsidian | ? | ❓ где лежат хранилища? В выгрузке их не видно — уточнить путь и забэкапить |
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
| Obsidian | `obsidian` | хранилища на Share или в git |
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
| Dion, eXpress (рабочие) | проверить Linux-клиенты на сайтах, иначе веб-версии | ❓ |
| Принтер Canon G3010 | `cups` + `cnijfilter2` (AUR) или драйвер без установки (IPP Everywhere) | |
| Мышь Logitech | `piper` (настройка кнопок/DPI) | G HUB на Linux нет |
| AdGuard | расширение в браузере (uBlock Origin / AdGuard) | |

**Не нужны на Linux:** balenaEtcher, Armbian Imager (`dd`/Impression), DiskInternals Linux Reader, Intel Driver Assistant, драйверы NVIDIA/Intel/Canon-утилиты Windows, Ruffle (есть в браузере).
