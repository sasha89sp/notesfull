#!/usr/bin/env python3
"""Windows: имя exe и заголовок окна ASRbox, иконка приложения."""
import pathlib
import re
import shutil

w = pathlib.Path('windows')
cm = w / 'CMakeLists.txt'
t = cm.read_text(encoding='utf-8')
t = re.sub(r'set\(BINARY_NAME "[^"]*"\)', 'set(BINARY_NAME "ASRbox")', t, count=1)
cm.write_text(t, encoding='utf-8')

main = w / 'runner/main.cpp'
s = main.read_text(encoding='utf-8')
s = re.sub(r'window\.Create\(L"[^"]*"', 'window.Create(L"ASRbox"', s, count=1)
main.write_text(s, encoding='utf-8')

ico = pathlib.Path('assets/icon/app_icon.ico')
if ico.exists():
    shutil.copy(ico, w / 'runner/resources/app_icon.ico')

rc = w / 'runner/Runner.rc'
if rc.exists():
    r = rc.read_text(encoding='utf-8')
    r = r.replace('"mysecure_notes"', '"ASRbox"').replace('mysecure_notes.exe', 'ASRbox.exe')
    rc.write_text(r, encoding='utf-8')
print('windows patched')
