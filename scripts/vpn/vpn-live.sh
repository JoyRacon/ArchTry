#!/usr/bin/env bash
# VPN в live-среде Arch (и на свежем Arch без графики): поднимает sing-box по config.json
# и готовит переменные прокси, чтобы curl, git и Claude Code ходили через VPN.
#
# Подготовка на Windows (см. docs/APPS.md, «VPN в live-среде»):
#   python links2singbox.py links.txt -o <флешка>\archtry\config.json
#   на флешке Ventoy папка archtry\: vpn-live.sh, config.json, sing-box (запасной бинарник)
#
# В live-Arch после подключения Wi-Fi:
#   mount --mkdir -o ro /dev/disk/by-label/Ventoy /mnt/usb
#   cp -r /mnt/usb/archtry /root/ && umount /mnt/usb
#   bash /root/archtry/vpn-live.sh             # поднять VPN
#   bash /root/archtry/vpn-live.sh --claude    # поднять VPN и поставить Claude Code
#   source /tmp/vpn.env                         # включить прокси в ТЕКУЩЕЙ консоли (обязательно)
#   claude
#
# Остановить VPN: pkill -x sing-box      Лог: /tmp/sing-box.log

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${CONF:-$DIR/config.json}"
LOG=/tmp/sing-box.log
ENV_FILE=/tmp/vpn.env

say()  { printf '\e[1;36m[*]\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m[OK]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[!]\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31m[X]\e[0m %s\n' "$*"; exit 1; }

[[ -f $CONF ]] || fail "Нет конфига: $CONF (сделать на Windows: links2singbox.py)"
PORT=$(grep -o '"listen_port": *[0-9]*' "$CONF" | head -1 | grep -o '[0-9]*$')
PORT=${PORT:-2080}

# 1. Clock: TLS and REALITY handshakes fail if the time is far off
timedatectl set-ntp true 2>/dev/null || true
say "Время (UTC): $(date -u '+%F %T')"
(( $(date +%Y) >= 2025 )) || warn "Часы явно неверные — VPN может не подключиться. Подождать минуту или: timedatectl set-time 'ГГГГ-ММ-ДД ЧЧ:ММ:СС'"

# 2. Internet without VPN
if curl -s -m 8 -o /dev/null https://archlinux.org || curl -s -m 8 -o /dev/null https://ya.ru; then
    ok "Интернет есть"
else
    warn "Интернет не отвечает. Wi-Fi: iwctl station wlan0 connect \"ИМЯ_СЕТИ\""
fi

# 3. sing-box: из репозитория Arch, иначе запасной бинарник с флешки
SB=$(command -v sing-box || true)
if [[ -z $SB ]]; then
    say "Ставлю sing-box из репозитория Arch..."
    pacman -Sy --noconfirm --needed sing-box >/tmp/pacman-sing-box.log 2>&1 && SB=$(command -v sing-box || true)
fi
if [[ -z $SB && -f $DIR/sing-box ]]; then
    say "Беру sing-box с флешки"
    install -m 755 "$DIR/sing-box" /usr/local/bin/sing-box && SB=/usr/local/bin/sing-box
fi
[[ -n $SB ]] || fail "sing-box не найден: нет ни в репозитории (см. /tmp/pacman-sing-box.log), ни на флешке"
ok "$($SB version | head -1)"

# 4. Проверка и запуск
"$SB" check -c "$CONF" || fail "Конфиг не прошёл проверку sing-box"
pkill -x sing-box 2>/dev/null && sleep 1
nohup "$SB" run -c "$CONF" >"$LOG" 2>&1 &
for _ in $(seq 1 20); do
    (echo >/dev/tcp/127.0.0.1/"$PORT") 2>/dev/null && break
    sleep 0.5
done
(echo >/dev/tcp/127.0.0.1/"$PORT") 2>/dev/null || { tail -20 "$LOG"; fail "sing-box не запустился"; }
ok "sing-box слушает 127.0.0.1:$PORT"

# 5. Переменные прокси для консоли
cat >"$ENV_FILE" <<EOF
# VPN proxy for this shell (sing-box mixed inbound)
export http_proxy=http://127.0.0.1:$PORT https_proxy=http://127.0.0.1:$PORT
export HTTP_PROXY=\$http_proxy HTTPS_PROXY=\$https_proxy
# Arch mirrors and local addresses go direct: faster and VPN is not needed for them
export no_proxy=localhost,127.0.0.1,::1,.archlinux.org,mirror.yandex.ru,geo.mirror.pkgbuild.com
export NO_PROXY=\$no_proxy
export PATH=\$HOME/.local/bin:\$PATH
EOF

# 6. Проверка, что VPN реально работает (urltest выбирает сервер пару секунд)
code=000
for _ in 1 2 3 4 5; do
    code=$(curl -s -m 15 --noproxy '' -x "http://127.0.0.1:$PORT" -o /dev/null -w '%{http_code}' https://api.anthropic.com || true)
    [[ $code != 000 ]] && break
    sleep 3
done
if [[ $code == 000 ]]; then
    tail -20 "$LOG"
    fail "Через VPN нет связи с api.anthropic.com. Смотреть лог выше / $LOG"
fi
country=$(curl -s -m 10 --noproxy '' -x "http://127.0.0.1:$PORT" https://ipinfo.io/country || true)
[[ $country =~ ^[A-Z]{2}$ ]] || country="?"
ok "VPN работает: api.anthropic.com отвечает (HTTP $code), выход через страну: ${country:-?}"

# 7. Claude Code (по флагу --claude)
if [[ ${1:-} == --claude ]]; then
    if mountpoint -q /run/archiso/cowspace; then
        mount -o remount,size=4G /run/archiso/cowspace && ok "Место в live-среде расширено до 4 ГБ"
    fi
    say "Ставлю git..."
    pacman -S --noconfirm --needed git >/dev/null 2>&1 || warn "git не поставился (не критично)"
    say "Ставлю Claude Code через VPN..."
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    curl -fsSL https://claude.ai/install.sh | bash || fail "Установка Claude Code не удалась"
    ok "Claude Code установлен"
fi

echo
say "Дальше в ЭТОЙ консоли выполнить:  source $ENV_FILE"
[[ ${1:-} == --claude ]] && say "Затем: git clone https://github.com/JoyRacon/ArchTry && cd ArchTry && claude"
say "Вход в Claude: откроется ссылка — открыть её на телефоне, код вставить сюда."
