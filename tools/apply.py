#!/usr/bin/env python3
"""Применяет ответ ИИ к проекту.
  python3 tools/apply.py ответ.txt
Формат ответа:
  === FILE: lib/путь.dart ===
  (полное содержимое файла)
  === END ===
  === DELETE: lib/старый.dart ===
Старые версии сохраняются в .apply_backup/<время>/. После применения пересобирается docs/CODEMAP.md."""
import re, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEAD = re.compile(r'^=== (FILE|DELETE): (.+?) ===\s*$')

def balanced(text):
    s = re.sub(r"'(?:\\.|[^'\\\n])*'|\"(?:\\.|[^\"\\\n])*\"", '""', text)
    s = re.sub(r'//[^\n]*', '', s)
    return [(a + b, s.count(a), s.count(b)) for a, b in ('{}', '()', '[]') if s.count(a) != s.count(b)]

def safe(rel):
    p = (ROOT / rel).resolve()
    if ROOT not in p.parents and p != ROOT:
        raise SystemExit(f'Путь вне проекта: {rel}')
    return p

def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    lines = Path(sys.argv[1]).read_text(encoding='utf-8').splitlines()
    ops, i = [], 0
    while i < len(lines):
        m = HEAD.match(lines[i])
        if not m:
            i += 1
            continue
        kind, rel = m.group(1), m.group(2).strip()
        if kind == 'DELETE':
            ops.append(('DELETE', rel, None))
            i += 1
            continue
        j = i + 1
        body = []
        while j < len(lines) and lines[j].strip() != '=== END ===':
            body.append(lines[j])
            j += 1
        if j >= len(lines):
            raise SystemExit(f'Нет «=== END ===» после {rel}: ответ обрезан, файл не применён.')
        if body and body[0].startswith('```'):
            body = body[1:]
        if body and body[-1].strip() == '```':
            body = body[:-1]
        ops.append(('FILE', rel, '\n'.join(body) + '\n'))
        i = j + 1
    if not ops:
        raise SystemExit('В ответе нет блоков «=== FILE: ... ===».')
    bak = ROOT / '.apply_backup' / time.strftime('%Y%m%d_%H%M%S')
    for kind, rel, text in ops:
        p = safe(rel)
        if p.exists():
            b = bak / rel
            b.parent.mkdir(parents=True, exist_ok=True)
            b.write_bytes(p.read_bytes())
        if kind == 'DELETE':
            if p.exists():
                p.unlink()
            print('удалён  ', rel)
            continue
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding='utf-8')
        bad = balanced(text) if rel.endswith('.dart') else []
        print('записан ', rel, ('  ВНИМАНИЕ: скобки не сходятся ' + str(bad)) if bad else '')
    subprocess.run([sys.executable, str(ROOT / 'tools' / 'codemap.py')], check=False)
    print('Готово. Резервные копии:', bak if bak.exists() else '(нечего копировать)')

if __name__ == '__main__':
    main()
