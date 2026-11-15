#!/usr/bin/env python3
"""Собирает docs/CODEMAP.md: карта файлов проекта.
Описания берутся из tools/file_notes.txt (файл | область | описание);
если файла там нет, берётся первый /// комментарий. Запуск: python3 tools/codemap.py"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AREAS = [('core', 'Ядро'), ('sync', 'Синхронизация и хранилища'), ('ui', 'Интерфейс и оболочка'),
         ('notes', 'Заметки'), ('shared', 'Общая папка'), ('pass', 'Пароли'),
         ('calendar', 'Календарь'), ('backup', 'Бэкап'), ('platform', 'Платформа'), ('?', 'Без области')]

def notes():
    d = {}
    p = ROOT / 'tools' / 'file_notes.txt'
    if p.exists():
        for ln in p.read_text(encoding='utf-8').splitlines():
            if ln.startswith('#') or '|' not in ln:
                continue
            f, a, t = [x.strip() for x in ln.split('|', 2)]
            d[f] = (a, t)
    return d

def info(path):
    t = path.read_text(encoding='utf-8')
    doc = next((m.group(1).strip() for m in re.finditer(r'^///\s?(.*)$', t, re.M)), '')
    classes = [c for c in re.findall(r'^(?:abstract |final )?(?:class|enum|mixin|extension) ([A-Za-z]\w*)', t, re.M)]
    funcs = [f for f in re.findall(r'^(?:Future<[^>]*>|Future|void|bool|String|int|double|List<[^>]*>|Widget|\w+) ([a-z]\w*)\(', t, re.M)
             if f not in ('main', 'build')][:6]
    return t.count('\n') + 1, doc, classes, funcs

def main():
    nt = notes()
    rows = {}
    big = []
    for p in sorted((ROOT / 'lib').glob('*.dart')):
        n, doc, cls, fn = info(p)
        area, desc = nt.get(p.name, ('?', doc or '(нет описания — добавьте в tools/file_notes.txt)'))
        rows.setdefault(area, []).append((p.name, n, desc, cls, fn))
        if n > 400:
            big.append((p.name, n))
    out = ['# CODEMAP — карта файлов', '',
           '_Создаётся автоматически: `python3 tools/codemap.py`. Описания: `tools/file_notes.txt`._', '']
    total = 0
    for key, title in AREAS:
        if key not in rows:
            continue
        out += [f'## {title}', '']
        for name, n, desc, cls, fn in rows[key]:
            total += n
            pub = [c for c in cls if not c.startswith('_')]
            extra = f' — `{", ".join(pub[:6])}`' if pub else (f' — `{", ".join(fn)}()`' if fn else '')
            out.append(f'- **lib/{name}** ({n}) {desc}{extra}')
        out.append('')
    tests = sorted((ROOT / 'tests').glob('*.dart'))
    out += ['## Тесты (tests/, при сборке копируются в test/)', ''] + \
           [f'- tests/{p.name} ({p.read_text(encoding="utf-8").count(chr(10)) + 1})' for p in tests] + ['']
    out += ['## Сборка и вспомогательные скрипты', '']
    for d in ('ci', 'tools'):
        for p in sorted((ROOT / d).glob('*.py')):
            out.append(f'- {d}/{p.name}')
    out += ['- .github/workflows/build.yml — CI: test, android, windows, linux, macos', '']
    out += [f'Всего в lib/: {total} строк.', '']
    if big:
        out += ['## Файлы больше 400 строк (кандидаты на дробление)', ''] + \
               [f'- lib/{n}: {c}' for n, c in sorted(big, key=lambda x: -x[1])] + ['']
    (ROOT / 'docs').mkdir(exist_ok=True)
    (ROOT / 'docs' / 'CODEMAP.md').write_text('\n'.join(out), encoding='utf-8')
    print('docs/CODEMAP.md обновлён,', total, 'строк в lib/')

if __name__ == '__main__':
    main()
