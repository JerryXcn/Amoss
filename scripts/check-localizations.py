#!/usr/bin/env python3
"""Check all owned UI copy has both translations and matching placeholders."""
from pathlib import Path
import json
import re
from collections import Counter
import os
os.chdir(Path(__file__).resolve().parent.parent)

keys = set()
han = re.compile(r'[\u3400-\u9fff]')

def scan(source, position=0, nested=False):
    result = ''
    depth = 0
    while position < len(source):
        if source.startswith('//', position):
            end = source.find('\n', position)
            if end < 0: end = len(source)
            result += source[position:end]
            position = end
        elif source.startswith('/*', position):
            end = source.index('*/', position) + 2
            result += source[position:end]
            position = end
        elif source.startswith('#"', position):
            end = source.index('"#', position + 2) + 2
            result += source[position:end]
            position = end
        elif source[position] == '"':
            start = position
            position += 1
            literal = '"'
            key = ''
            count = 0
            while position < len(source):
                if source.startswith('\\(', position):
                    expression, position = scan(source, position + 2, True)
                    literal += '\\(' + expression + ')'
                    key += '{' + str(count) + '}'
                    count += 1
                elif source[position] == '\\':
                    pair = source[position:position+2]
                    literal += pair
                    key += {'\\n': '\n', '\\t': '\t', '\\r': '\r', '\\"': '"', '\\\\': '\\'}.get(pair, pair)
                    position += 2
                elif source[position] == '"':
                    literal += '"'
                    position += 1
                    break
                else:
                    literal += source[position]
                    key += source[position]
                    position += 1
            if han.search(key) and key != '中文（简体）':
                keys.add(key)
                if not re.search(r'L10n\.text\(\s*$', source[:start]):
                    literal = 'L10n.text(' + literal + ')'
            result += literal
        elif nested and source[position] == ')' and depth == 0:
            return result, position + 1
        else:
            if nested:
                if source[position] == '(': depth += 1
                elif source[position] == ')': depth -= 1
            result += source[position]
            position += 1
    return result, position

paths = list(Path('Sources/Amoss').glob('*.swift')) + list(Path('Sources/AmossCore').glob('*.swift'))
paths += list(Path('Integrations/Scrcpy').glob('*.swift'))
for path in paths:
    original = path.read_text()
    result, _ = scan(original)
    if result != original:
        raise SystemExit(f'Unlocalized interface text in {path}')

def catalog(language):
    path = Path(f'Sources/AmossCore/Resources/{language}.lproj/Localizable.strings')
    result = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith('/*'): continue
        match = re.fullmatch(r'("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");', line)
        if not match: raise SystemExit(f'Malformed localization line in {path}: {line}')
        key, value = [json.loads(item) for item in match.groups()]
        if key in result: raise SystemExit(f'Duplicate key in {path}: {key}')
        result[key] = value
    return result

english, chinese = catalog('en'), catalog('zh-Hans')
if set(english) != keys or set(chinese) != keys:
    raise SystemExit(f'Catalog mismatch. Missing English: {keys - set(english)}; missing Chinese: {keys - set(chinese)}; unused: {set(english) - keys}')
for key in keys:
    expected = Counter(re.findall(r'\{\d+\}', key))
    for name, values in [('en', english), ('zh-Hans', chinese)]:
        if not values[key] or Counter(re.findall(r'\{\d+\}', values[key])) != expected:
            raise SystemExit(f'Invalid translation placeholders ({name}): {key}')
    if han.search(english[key]): raise SystemExit(f'Chinese remains in English translation: {key}')
print(f'Localization verified: {len(keys)} keys, Chinese/English coverage and placeholders match.')
