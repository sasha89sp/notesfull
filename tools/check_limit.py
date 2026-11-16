#!/usr/bin/env python3
"""Ориентир (не жёсткое правило): файл ~300–400 строк, резать по смыслу.
Скрипт только предупреждает, код возврата всегда 0.
Запуск: python3 tools/check_limit.py"""
import glob, sys
sys.path.insert(0, __file__.rsplit('/', 1)[0] + '/../../scratch') if False else None
bad = 0
for f in sorted(glob.glob('lib/*.dart') + glob.glob('tests/*.dart') + glob.glob('variants/*/*.dart')):
    n = open(f, encoding='utf-8').read().count('\n')
    if n > 300:
        print('предупреждение: >300 строк:', f, n); bad += 1
print('OK' if not bad else f'{bad} файлов длиннее 300 строк (это только ориентир)')
