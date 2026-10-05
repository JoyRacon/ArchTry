# Приложения: что есть на Windows и что с ними будет

Полный список собирает `scripts/windows/inventory.ps1` (см. INSTALL.md, шаг 0).
Результат `public.zip` разбираем вместе с Claude и заполняем таблицу ниже.

> 🔒 Конфиги VPN, SSH-ключи, Tabby и пароли Wi-Fi — **только на внешнем диске**, никогда в этот репозиторий.

## Критичные: без них нет работы или нет Claude

| Программа | Зачем | Что сохранить до стирания | На Arch | Статус |
|---|---|---|---|---|
| **Throne** (sing-box, бывший Nekoray) | VPN → доступ к Claude | папка `config` рядом с exe + ссылки профилей (ПКМ → Share → Copy link) | Throne для Linux (проверить AUR `throne`/`throne-bin` или релиз на GitHub) либо `sing-box` из репозитория + JSON-конфиг | ⏳ |
| **WireGuard** | работа | Export tunnels to zip (файлы в Program Files зашифрованы, копировать бесполезно) | `wireguard-tools`, импорт: `nmcli connection import type wireguard file wg0.conf` | ⏳ |
| **Tabby** | SSH по работе | `%APPDATA%\tabby\config.yaml` + мастер-пароль vault, если включён | `tabby-bin` из AUR, тот же `config.yaml` в `~/.config/tabby/` | ⏳ |
| **Рабочий VPN** | работа | зависит от клиента | зависит от клиента (см. Q5) | ❓ какой клиент? |
| SSH-ключи | серверы, GitHub | `%USERPROFILE%\.ssh` | `~/.ssh`, права `chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*` | ⏳ |

Варианты рабочего VPN на Linux: Cisco AnyConnect → `openconnect`; FortiClient → `openfortivpn`;
OpenVPN → `networkmanager-openvpn`; GlobalProtect → `openconnect --protocol=gp`; Check Point → `snx-rs` (AUR); встроенный VPN Windows (L2TP/IKEv2) → плагины NetworkManager.

## Доступ к Claude во время установки

Claude открывается только через VPN, а на чистой системе VPN ещё нет. Поэтому:

1. **Live-USB и разметка:** Claude на телефоне (claude.ai/code через VPN на телефоне). На ноутбуке Claude в это время не нужен.
2. **Первая загрузка Arch, ещё без графики:** поднять `sing-box` из консоли по конфигу из Throne, затем Claude Code CLI.
   Готовый JSON для sing-box соберём заранее из ссылок профилей и проверим ещё в live-среде (INSTALL.md, шаг 1).
3. **После Hyprland:** Throne с графическим интерфейсом, как сейчас на Windows.

## Остальные программы

Заполняется по результатам инвентаризации: остаётся на Windows / переезжает на Arch / не нужна.

| Программа | Решение | Комментарий |
|---|---|---|
| Visual Studio | Windows | только Windows |
| Ableton, FL Studio, Guitar Rig, VST/ASIO | Windows | аудио-стек остаётся там; проекты на Share `audio/` |
| LM Studio | ? | на Linux есть AppImage; модели большие, можно положить на Share |
| Creality (слайсер) | ? | на Linux есть Creality Print / OrcaSlicer (AppImage) |
| Blender | Arch | проекты .blend/.stl на Share `3d/` |
| VS Code | Arch (+ Windows) | `vscode-extensions.txt` из инвентаризации → поставить те же расширения |
| Игры | Windows | |
