#!/usr/bin/env python3
"""Validate package edges and page isolation; never open hardware or user state."""
import json, pathlib, re, subprocess, argparse
ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--page')
parser.add_argument('--shared', action='store_true')
args = parser.parse_args()
EDGES = {'PopupBookCore': set(), 'PopupBookRuntime': {'PopupBookCore'}, 'PageTransport': {'PopupBookCore'}, 'MacPlatform': {'PopupBookCore', 'PageTransport'}, 'SceneKitRendering': {'PopupBookCore'}, 'PageWorkerKit': {'PopupBookCore', 'PageTransport'}, 'BookHostApp': {'PopupBookCore', 'PopupBookRuntime', 'MacPlatform', 'PageTransport'}}
package = json.loads(subprocess.check_output(['swift', 'package', 'dump-package'], cwd=ROOT))
for target in package['targets']:
    name = target['name']
    if name not in EDGES:
        continue
    deps = {d.get('byName', d.get('target', [None]))[0] for d in target['dependencies']}
    assert deps == EDGES[name], f'{name}依赖越界：{deps}'
    for source in (ROOT / target['path']).rglob('*.swift'):
        text = source.read_text()
        imports = set(re.findall('^import (\\w+)', text, re.M))
        if name in {'PopupBookCore', 'PopupBookRuntime'}:
            assert imports <= {'Foundation'} | EDGES[name], f'纯逻辑模块依赖平台：{source}'
        assert not re.search('\\b(?:CatPose|CatMood|PaperCat|ForestCabin)\\b', text), f'公共模块认识场景：{source}'
        assert not re.search('/Users/|mac-duo|open_resource_project', text), f'存在外部工作目录依赖：{source}'
scene_sources = [] if args.shared else list((ROOT / 'Scenes' / args.page / 'Sources').rglob('*.swift')) if args.page else list((ROOT / 'Scenes').glob('*/Sources/**/*.swift'))
for source in scene_sources:
    text = source.read_text()
    module = source.parts[source.parts.index('Sources') + 1]
    if module.endswith('Behavior'):
        imports = set(re.findall('^import (\\w+)', text, re.M))
        assert imports <= {'Foundation', 'PopupBookCore'}, f'场景行为模块依赖表现或平台：{source}'
    assert not re.search('^import (?:MacPlatform|IOKit|AVFoundation|SwiftUI)\\b', text, re.M), f'场景绕过平台边界：{source}'
    assert not re.search('(?:IOHID|UserDefaults.standard|FileStateStore|SystemFrameClock)', text), f'场景直接访问设备、设置或存储：{source}'
    assert 'fatalError(' not in text and 'try!' not in text, f'场景必须报告错误：{source}'
print('公共模块依赖与独立场景副作用边界检查通过。')
