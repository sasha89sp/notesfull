#!/usr/bin/env python3
"""Комплект для нового чата с ИИ.
  python3 tools/brief.py                 — только документы и карта (без кода)
  python3 tools/brief.py editor md_ops   — плюс указанные файлы (по имени без .dart или по пути)
Результат: brief.txt в корне проекта. Его вставляют/прикладывают в новый чат."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ['docs/HANDOFF.md', 'docs/ARCHITECTURE.md', 'docs/DECISIONS.md', 'docs/CODEMAP.md']

def find(name):
    p = ROOT / name
    if p.is_file():
        return [p]
    hits = [x for x in (ROOT / 'lib').glob('*.dart') if x.stem == name.replace('.dart', '')]
    hits += [x for x in (ROOT / 'tests').glob('*.dart') if x.stem == name.replace('.dart', '')]
    return hits

def main():
    parts, total = [], 0
    for d in DOCS:
        p = ROOT / d
        if p.exists():
            t = p.read_text(encoding='utf-8')
            parts.append(f'===== {d} =====\n{t}\n')
            total += len(t)
    docs_len = total
    for name in sys.argv[1:]:
        fs = find(name)
        if not fs:
            print('не найден:', name)
            continue
        for f in fs:
            t = f.read_text(encoding='utf-8')
            rel = f.relative_to(ROOT).as_posix()
            parts.append(f'===== FILE {rel} =====\n{t}\n')
            total += len(t)
    out = ROOT / 'brief.txt'
    out.write_text('\n'.join(parts), encoding='utf-8')
    print(f'brief.txt: {total} символов (~{total // 3} токенов), из них документы ~{docs_len // 3}')
    if total // 3 > 60000:
        print('ВНИМАНИЕ: комплект большой; уменьшите число файлов.')

if __name__ == '__main__':
    main()
