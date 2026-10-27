#!/usr/bin/env python3
"""Validate package edges and page isolation; never open hardware or user state."""
import json,pathlib,re,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
EDGES={
 'PopupBookCore':set(),'PopupBookRuntime':{'PopupBookCore'},'PageTransport':{'PopupBookCore'},
 'MacPlatform':{'PopupBookCore','PageTransport'},'SceneKitRendering':{'PopupBookCore'},
 'PageWorkerKit':{'PopupBookCore','PageTransport'},'BookHostApp':{'PopupBookCore','PopupBookRuntime','MacPlatform','PageTransport'}}
package=json.loads(subprocess.check_output(['swift','package','dump-package'],cwd=ROOT))
for target in package['targets']:
 name=target['name']
 if name not in EDGES:continue
 deps={d.get('byName',d.get('target',[None]))[0]for d in target['dependencies']}
 assert deps==EDGES[name],f'{name}依赖越界：{deps}'
 for source in (ROOT/target['path']).rglob('*.swift'):
  text=source.read_text();imports=set(re.findall(r'^import (\w+)',text,re.M))
  if name in {'PopupBookCore','PopupBookRuntime'}:
   assert imports <= {'Foundation'}|EDGES[name],f'纯逻辑模块依赖平台：{source}'
  assert not re.search(r'\b(?:CatPose|CatMood|PaperCat|ForestCabin)\b',text),f'公共模块认识场景：{source}'
  assert not re.search(r'/Users/|mac-duo|open_resource_project',text),f'存在外部工作目录依赖：{source}'
for source in (ROOT/'Scenes').glob('*/Sources/**/*.swift'):
 text=source.read_text()
 assert not re.search(r'^import (?:MacPlatform|IOKit|AVFoundation|SwiftUI)\b',text,re.M),f'场景绕过平台边界：{source}'
 assert not re.search(r'(?:IOHID|UserDefaults.standard|FileStateStore|SystemFrameClock)',text),f'场景直接访问设备、设置或存储：{source}'
 assert 'fatalError(' not in text and 'try!' not in text,f'场景必须报告错误：{source}'
print('公共模块依赖与独立场景副作用边界检查通过。')
