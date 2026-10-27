#!/usr/bin/env python3
"""Check module-owned catalogs and format argument parity without changing system language."""
import argparse
import json
import pathlib
import re
ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--page')
parser.add_argument('--shared', action='store_true')
args = parser.parse_args()
count = 0
for catalog in ROOT.glob('**/Resources/en.lproj/Localizable.strings'):
    if any((part.startswith('.') or part == 'build' for part in catalog.relative_to(ROOT).parts)):
        continue

    def read(path):
        result = {}
        for line in path.read_text().splitlines():
            match = re.fullmatch('("(?:\\\\.|[^"\\\\])*") = ("(?:\\\\.|[^"\\\\])*");', line)
            if not match:
                raise ValueError(f'无效语言资源行：{path}: {line}')
            (key, value) = map(json.loads, match.groups())
            if key in result:
                raise ValueError(f'重复翻译键：{path}: {key}')
            result[key] = value
        return result
    relative = catalog.relative_to(ROOT)
    if args.page and (not str(relative).startswith('Scenes/' + args.page + '/')):
        continue
    if args.shared and relative.parts[0] not in {'Modules', 'Apps'}:
        continue
    english = read(catalog)
    chinese = read(catalog.parent.parent / 'zh-Hans.lproj/Localizable.strings')
    assert english.keys() == chinese.keys(), f'中英文键不一致：{catalog}'
    for (key, value) in english.items():
        assert not re.search('[\\u4e00-\\u9fff]', value), f'英文缺少翻译：{key}'
        assert value.count('%@') == chinese[key].count('%@'), f'格式参数不匹配：{key}'
    module = catalog.parents[2]
    for source in module.rglob('*.swift'):
        for key in re.findall('L10n\\.text\\(\\s*"([^"\\n]+)"', source.read_text()):
            assert key in english, f'文案未加入资源：{source}: {key}'
    count += len(english)
print(f'中英文语言资源、调用键和格式参数检查通过：{count}条。')
