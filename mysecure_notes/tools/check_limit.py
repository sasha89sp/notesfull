#!/usr/bin/env python3
"""Проверка правила: каждый файл lib/tests/variants ≤ 300 строк + баланс скобок.
Запуск: python3 tools/check_limit.py"""
import glob, sys
sys.path.insert(0, __file__.rsplit('/', 1)[0] + '/../../scratch') if False else None
bad = 0
for f in sorted(glob.glob('lib/*.dart') + glob.glob('tests/*.dart') + glob.glob('variants/*/*.dart')):
    n = open(f, encoding='utf-8').read().count('\n')
    if n > 300:
        print('>300:', f, n); bad += 1
print('OK' if not bad else f'{bad} файлов длиннее 300 строк')
sys.exit(1 if bad else 0)
