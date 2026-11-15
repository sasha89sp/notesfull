#!/usr/bin/env python3
"""Добавляет права macOS-приложению: сеть, файлы, микрофон."""
import pathlib

keys = {
    'com.apple.security.network.client': '<true/>',
    'com.apple.security.files.user-selected.read-write': '<true/>',
    'com.apple.security.device.audio-input': '<true/>',
}
for f in pathlib.Path('macos/Runner').glob('*.entitlements'):
    t = f.read_text(encoding='utf-8')
    for k, v in keys.items():
        if k not in t:
            t = t.replace('</dict>', f'\t<key>{k}</key>\n\t{v}\n</dict>', 1)
    f.write_text(t, encoding='utf-8')

info = pathlib.Path('macos/Runner/Info.plist')
if info.exists():
    t = info.read_text(encoding='utf-8')
    if 'NSMicrophoneUsageDescription' not in t:
        t = t.replace('</dict>', '\t<key>NSMicrophoneUsageDescription</key>\n\t<string>Запись голосовых заметок</string>\n</dict>', 1)
        info.write_text(t, encoding='utf-8')
print('macos patched')
