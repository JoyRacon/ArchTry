#!/usr/bin/env python3
"""
Конвертер ссылок VPN (как в Throne / v2rayN) в конфиг sing-box.

Поддерживается: vless (tls/reality, tcp/ws/grpc/httpupgrade/h2), trojan, vmess, ss (shadowsocks),
hysteria2 (hy2), tuic, а также ссылки на подписки (https://...), которые отдают список таких ссылок.

Запуск (Windows, Python уже установлен):
    python links2singbox.py links.txt -o E:\\iso\\archtry\\config.json
    python links2singbox.py links.txt -o config.json --tun     # системный VPN (для установленного Arch)

links.txt — по одной ссылке на строку (ПКМ по профилю в Throne → Share → Copy link).
В ссылках ключи доступа: links.txt и config.json НЕ коммитить и никуда не отправлять.

Режимы:
  по умолчанию — локальный прокси 127.0.0.1:2080 (HTTP + SOCKS5). Программы идут через VPN,
                 если задать им HTTPS_PROXY (vpn-live.sh делает это сам). Работает везде, без root.
  --tun        — весь трафик системы через VPN (нужен root). Для установленного Arch.
"""
import argparse
import base64
import json
import re
import sys
import urllib.parse
import urllib.request

TEST_URL = "https://www.gstatic.com/generate_204"


class LinkError(ValueError):
    pass


def b64decode(text: str) -> str:
    text = text.strip().replace("-", "+").replace("_", "/")
    text += "=" * (-len(text) % 4)
    return base64.b64decode(text).decode("utf-8")


def q1(qs: dict, key: str, default=None):
    value = qs.get(key)
    return value[0] if value else default


def is_true(value) -> bool:
    return str(value).lower() in ("1", "true", "yes")


def tls_block(qs: dict, host: str, default_security: str = "none"):
    security = (q1(qs, "security") or default_security).lower()
    if security in ("none", ""):
        return None
    tls = {"enabled": True, "server_name": q1(qs, "sni") or q1(qs, "peer") or host}
    if is_true(q1(qs, "allowInsecure")) or is_true(q1(qs, "insecure")):
        tls["insecure"] = True
    if q1(qs, "alpn"):
        tls["alpn"] = [a for a in q1(qs, "alpn").split(",") if a]
    fp = q1(qs, "fp")
    if security == "reality":
        if not q1(qs, "pbk"):
            raise LinkError("reality без pbk (public key)")
        tls["utls"] = {"enabled": True, "fingerprint": fp or "chrome"}
        tls["reality"] = {"enabled": True, "public_key": q1(qs, "pbk"), "short_id": q1(qs, "sid", "")}
    elif fp:
        tls["utls"] = {"enabled": True, "fingerprint": fp}
    return tls


def transport_block(qs: dict):
    kind = (q1(qs, "type") or "tcp").lower()
    host = q1(qs, "host")
    path = q1(qs, "path") or "/"
    if kind in ("tcp", "raw"):
        if (q1(qs, "headerType") or "").lower() == "http":
            return {"type": "http", "host": [host] if host else [], "path": path}
        return None
    if kind == "ws":
        transport = {"type": "ws", "path": path}
        match = re.search(r"[?&]ed=(\d+)", path)
        if match:  # early data in path: /ws?ed=2048
            transport["path"] = re.sub(r"[?&]ed=\d+", "", path) or "/"
            transport["max_early_data"] = int(match.group(1))
            transport["early_data_header_name"] = "Sec-WebSocket-Protocol"
        if host:
            transport["headers"] = {"Host": host}
        return transport
    if kind == "grpc":
        return {"type": "grpc", "service_name": q1(qs, "serviceName") or q1(qs, "path") or ""}
    if kind == "httpupgrade":
        transport = {"type": "httpupgrade", "path": path}
        if host:
            transport["host"] = host
        return transport
    if kind in ("h2", "http"):
        return {"type": "http", "host": [host] if host else [], "path": path}
    raise LinkError(f"транспорт '{kind}' sing-box не поддерживает (xhttp/splithttp/kcp — только в Xray)")


def attach(outbound: dict, tls, transport):
    if tls:
        outbound["tls"] = tls
    if transport:
        outbound["transport"] = transport
    return outbound


def split_url(link: str):
    parts = urllib.parse.urlsplit(link)
    if not parts.hostname or not parts.port:
        raise LinkError("нет адреса сервера или порта")
    qs = urllib.parse.parse_qs(parts.query, keep_blank_values=True)
    name = urllib.parse.unquote(parts.fragment) or f"{parts.hostname}:{parts.port}"
    userinfo = urllib.parse.unquote(parts.netloc.rsplit("@", 1)[0]) if "@" in parts.netloc else ""
    return parts, qs, name, userinfo


def parse_vless(link: str):
    parts, qs, name, userinfo = split_url(link)
    ob = {"type": "vless", "server": parts.hostname, "server_port": parts.port, "uuid": userinfo}
    if q1(qs, "flow"):
        ob["flow"] = q1(qs, "flow")
    if q1(qs, "packetEncoding"):
        ob["packet_encoding"] = q1(qs, "packetEncoding")
    return name, attach(ob, tls_block(qs, parts.hostname), transport_block(qs))


def parse_trojan(link: str):
    parts, qs, name, userinfo = split_url(link)
    ob = {"type": "trojan", "server": parts.hostname, "server_port": parts.port, "password": userinfo}
    return name, attach(ob, tls_block(qs, parts.hostname, default_security="tls"), transport_block(qs))


def parse_vmess(link: str):
    data = json.loads(b64decode(link[len("vmess://"):]))
    host = data.get("add")
    if not host or not data.get("port"):
        raise LinkError("нет адреса сервера или порта")
    net = (data.get("net") or "tcp").lower()
    qs = {
        "security": ["tls" if str(data.get("tls", "")).lower() == "tls" else "none"],
        "sni": [data.get("sni") or ""], "alpn": [data.get("alpn") or ""], "fp": [data.get("fp") or ""],
        "type": [net], "host": [data.get("host") or ""], "path": [data.get("path") or ""],
        "serviceName": [data.get("path") or ""], "headerType": [data.get("type") or ""],
    }
    qs = {k: v for k, v in qs.items() if v[0]}
    ob = {"type": "vmess", "server": host, "server_port": int(data["port"]), "uuid": data.get("id"),
          "security": data.get("scy") or "auto", "alter_id": int(data.get("aid") or 0)}
    return data.get("ps") or f"{host}:{data['port']}", attach(ob, tls_block(qs, host), transport_block(qs))


def parse_ss(link: str):
    body, _, fragment = link[len("ss://"):].partition("#")
    name = urllib.parse.unquote(fragment)
    if "@" not in body.split("?")[0].split("/")[0]:  # legacy: ss://BASE64(method:pass@host:port)
        body = b64decode(body.split("?")[0].split("/")[0]) + body[len(body.split("?")[0].split("/")[0]):]
    userinfo, hostpart = body.rsplit("@", 1)
    userinfo = urllib.parse.unquote(userinfo)
    if ":" not in userinfo:
        userinfo = b64decode(userinfo)
    method, password = userinfo.split(":", 1)
    parts = urllib.parse.urlsplit("ss://x@" + hostpart)
    if not parts.hostname or not parts.port:
        raise LinkError("нет адреса сервера или порта")
    ob = {"type": "shadowsocks", "server": parts.hostname, "server_port": parts.port,
          "method": method, "password": password}
    plugin = q1(urllib.parse.parse_qs(parts.query), "plugin")
    if plugin:
        plugin_name, _, plugin_opts = plugin.partition(";")
        ob["plugin"] = plugin_name
        if plugin_opts:
            ob["plugin_opts"] = plugin_opts
    return name or f"{parts.hostname}:{parts.port}", ob


def parse_hysteria2(link: str):
    parts, qs, name, userinfo = split_url(re.sub(r"^hy2://", "hysteria2://", link))
    tls = {"enabled": True, "server_name": q1(qs, "sni") or parts.hostname, "alpn": ["h3"]}
    if is_true(q1(qs, "insecure")):
        tls["insecure"] = True
    ob = {"type": "hysteria2", "server": parts.hostname, "server_port": parts.port, "password": userinfo, "tls": tls}
    if q1(qs, "obfs"):
        ob["obfs"] = {"type": q1(qs, "obfs"), "password": q1(qs, "obfs-password", "")}
    return name, ob


def parse_tuic(link: str):
    parts, qs, name, userinfo = split_url(link)
    uuid, _, password = userinfo.partition(":")
    tls = {"enabled": True, "server_name": q1(qs, "sni") or parts.hostname,
           "alpn": [a for a in (q1(qs, "alpn") or "h3").split(",") if a]}
    if is_true(q1(qs, "allow_insecure")) or is_true(q1(qs, "insecure")):
        tls["insecure"] = True
    ob = {"type": "tuic", "server": parts.hostname, "server_port": parts.port, "uuid": uuid, "password": password,
          "congestion_control": q1(qs, "congestion_control", "bbr"), "tls": tls}
    if q1(qs, "udp_relay_mode"):
        ob["udp_relay_mode"] = q1(qs, "udp_relay_mode")
    return name, ob


PARSERS = {"vless": parse_vless, "trojan": parse_trojan, "vmess": parse_vmess, "ss": parse_ss,
           "hysteria2": parse_hysteria2, "hy2": parse_hysteria2, "tuic": parse_tuic}


def expand_lines(lines):
    """Ссылки как есть; https:// — подписка (скачать); строка base64 — список ссылок."""
    for raw in lines:
        line = raw.strip().lstrip("\ufeff")
        if not line or line.startswith("#"):
            continue
        if line.startswith(("http://", "https://")):
            print(f"[*] подписка: {line.split('?')[0]}", file=sys.stderr)
            req = urllib.request.Request(line, headers={"User-Agent": "sing-box"})
            text = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "replace")
            if "://" not in text:
                text = b64decode(text)
            yield from expand_lines(text.splitlines())
        elif "://" in line:
            yield line
        else:
            try:
                yield from expand_lines(b64decode(line).splitlines())
            except Exception:
                print(f"[!] не ссылка, пропускаю: {line[:30]}...", file=sys.stderr)


def unique_tag(name: str, used: set) -> str:
    tag = re.sub(r"\s+", " ", name).strip()[:60] or "node"
    base, n = tag, 2
    while tag in used:
        tag, n = f"{base} #{n}", n + 1
    used.add(tag)
    return tag


def build_config(nodes, port: int, tun: bool) -> dict:
    tags = [ob["tag"] for ob in nodes]
    outbounds = list(nodes)
    if len(nodes) > 1:  # several servers: pick the fastest automatically
        outbounds.insert(0, {"type": "urltest", "tag": "auto", "outbounds": tags, "url": TEST_URL, "interval": "3m"})
    final = "auto" if len(nodes) > 1 else tags[0]
    outbounds.append({"type": "direct", "tag": "direct"})

    config = {
        "log": {"level": "info", "timestamp": True},
        "dns": {"servers": [{"type": "local", "tag": "dns-local"}]},
        "inbounds": [{"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": port}],
        "outbounds": outbounds,
        "route": {"final": final, "default_domain_resolver": "dns-local"},
    }
    if tun:
        config["dns"] = {
            "servers": [
                {"type": "https", "tag": "dns-remote", "server": "1.1.1.1", "detour": final},
                {"type": "local", "tag": "dns-local"},
            ],
            "final": "dns-remote",
        }
        config["inbounds"].append({"type": "tun", "tag": "tun-in", "interface_name": "singbox0",
                                   "address": ["172.19.0.1/30"], "auto_route": True, "strict_route": True})
        config["route"].update({
            "auto_detect_interface": True,
            "rules": [
                {"action": "sniff"},
                {"protocol": "dns", "action": "hijack-dns"},
                {"ip_is_private": True, "outbound": "direct"},
            ],
        })
    return config


def main():
    ap = argparse.ArgumentParser(description="VPN links (vless/trojan/vmess/ss/hy2/tuic) -> sing-box config")
    ap.add_argument("links", help="файл со ссылками, по одной на строку ('-' = stdin)")
    ap.add_argument("-o", "--output", default="config.json")
    ap.add_argument("--port", type=int, default=2080, help="порт локального прокси (по умолчанию 2080)")
    ap.add_argument("--tun", action="store_true", help="добавить TUN: весь трафик системы через VPN")
    args = ap.parse_args()

    source = sys.stdin if args.links == "-" else open(args.links, encoding="utf-8-sig")
    nodes, used, errors = [], set(), 0
    for link in expand_lines(source.read().splitlines()):
        scheme = link.split("://", 1)[0].lower()
        parser = PARSERS.get(scheme)
        if not parser:
            print(f"[!] протокол '{scheme}' не поддерживается, пропускаю", file=sys.stderr)
            errors += 1
            continue
        try:
            name, outbound = parser(link)
        except Exception as exc:  # keep going: one bad link must not kill the rest
            print(f"[!] {scheme}: {exc} — пропускаю", file=sys.stderr)
            errors += 1
            continue
        outbound = {"tag": unique_tag(name, used), **outbound}
        nodes.append(outbound)
        print(f"[+] {scheme:9} {outbound['tag']}  ({outbound['server']}:{outbound['server_port']})", file=sys.stderr)

    if not nodes:
        sys.exit("Ни одной рабочей ссылки — конфиг не создан.")
    with open(args.output, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(build_config(nodes, args.port, args.tun), fh, ensure_ascii=False, indent=2)
    print(f"Готово: {args.output} — серверов: {len(nodes)}, пропущено: {errors}", file=sys.stderr)


if __name__ == "__main__":
    main()
