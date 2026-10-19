#!/usr/bin/env python3
"""Добавляет строки в Localizable.xcstrings вместе с русским переводом.

    python3 scripts/add_strings.py "English key=Русский перевод" ...

`xcodebuild` сам ключи в каталог не дописывает, а `LocalizationTests` требует перевод
у каждой строки — скрипт держит формат каталога таким же, как у Xcode.
"""
import json
import sys
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "AIChat/Resources/Localizable.xcstrings"
catalog = json.loads(path.read_text(encoding="utf-8"))
for pair in sys.argv[1:]:
    key, _, russian = pair.partition("=")
    if not key or not russian:
        sys.exit(f"Ожидается «key=перевод»: {pair}")
    entry = catalog["strings"].setdefault(key, {})
    entry.setdefault("localizations", {})["ru"] = {"stringUnit": {"state": "translated", "value": russian}}
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : ")) + "\n",
                encoding="utf-8")
print(f"OK: {len(sys.argv) - 1} strings")
