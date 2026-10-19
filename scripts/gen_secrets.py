#!/usr/bin/env python3
"""Генерирует AIChat/Data/Secrets/Secrets.generated.swift с обфусцированными ключами.

Ключи берутся ТОЛЬКО из переменных окружения, чтобы они не попадали ни в чат
с агентом, ни в логи, ни в git открытым текстом:

    NEBULA_API_TOKEN=eyJ... APPHUD_API_KEY=app_... python3 scripts/gen_secrets.py

- NEBULA_API_TOKEN — Bearer-токен владельца для Dola и PixVerse API;
- APPHUD_API_KEY — API-ключ проекта Apphud.

Схема: каждый ключ XOR со случайной солью той же длины. В файле лежат массивы
байт; строка собирается только в рантайме. Это защита от grep и сканеров
секретов, а не от реверса — настоящая защита требует своего прокси-сервера.
"""
import os
import secrets
import sys
from pathlib import Path

KEYS = {
    # имя свойства в Swift: переменная окружения
    "nebulaAPIToken": "NEBULA_API_TOKEN",
    "apphudAPIKey": "APPHUD_API_KEY",
}

values = {name: os.environ.get(env, "").strip() for name, env in KEYS.items()}
missing = [KEYS[name] for name, value in values.items() if not value]
if missing:
    sys.exit("Задайте переменные окружения: " + ", ".join(missing))


def swift_array(data: bytes) -> str:
    lines = []
    for i in range(0, len(data), 12):
        lines.append("        " + ", ".join(f"0x{b:02X}" for b in data[i:i + 12]))
    return "[\n" + ",\n".join(lines) + "\n    ]"


blocks = []
for name, value in values.items():
    raw = value.encode("utf-8")
    salt = secrets.token_bytes(len(raw))
    mixed = bytes(a ^ b for a, b in zip(raw, salt))
    blocks.append(f"""    private static let {name}Salt: [UInt8] = {swift_array(salt)}

    private static let {name}Mixed: [UInt8] = {swift_array(mixed)}

    static var {name}: String {{
        String(decoding: zip({name}Mixed, {name}Salt).map {{ $0 ^ $1 }}, as: UTF8.self)
    }}""")

out = """// Сгенерировано scripts/gen_secrets.py — не редактировать вручную.
// Ключи обфусцированы (XOR с солью), открытым текстом в репозитории их нет.

enum Secrets {
""" + "\n\n".join(blocks) + "\n}\n"

path = Path(__file__).resolve().parent.parent / "AIChat/Data/Secrets/Secrets.generated.swift"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(out, encoding="utf-8")
print(f"OK: {path.relative_to(Path.cwd()) if path.is_relative_to(Path.cwd()) else path}")
