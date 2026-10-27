#!/usr/bin/env python3
"""Editor-neutral page development commands. A page never modifies host package registration."""
import argparse, json, pathlib, re, shutil, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]

def run(args):
    subprocess.run(args, cwd=ROOT, check=True)

def pages(strict=False):
    result = []
    for path in sorted((ROOT / 'Scenes').glob('*/page.json')):
        try:
            data = json.loads(path.read_text())
            assert data['id'] == path.parent.name and data['contractVersion'] == 1
            result.append(data)
        except Exception as e:
            if strict:
                raise SystemExit('无效场景描述：' + str(path))
            print('已隔离无效开发描述：', path, e, file=sys.stderr)
    return result
parser = argparse.ArgumentParser(description='场景开发与集成命令')
parser.add_argument('action', choices=['list', 'check', 'build', 'preview', 'new'])
parser.add_argument('page', nargs='?')
parser.add_argument('--strict', action='store_true')
args = parser.parse_args()
if args.action == 'list':
    print(json.dumps([p['id'] for p in pages(strict=args.strict)]))
else:
    id = args.page
    if not id or not re.fullmatch('[a-z][a-z0-9-]{0,63}', id):
        parser.error('请提供合法场景标识')
    if ROOT.name == id:
        raise SystemExit('工作目录不能与场景标识同名，请使用mac-popup-book-<id>作为工作目录名以避免Swift包身份碰撞')
    package = ROOT / 'Scenes' / id
    if args.action == 'new':
        if package.exists():
            raise SystemExit('场景目录已存在，不覆盖')
        shutil.copytree(ROOT / 'Templates/Page', package)
        for file in package.rglob('*'):
            if file.is_file():
                file.write_text(file.read_text().replace('__PAGE_ID__', id).replace('__SERVICE_ID__', 'local.ssr.forestbook.page.' + id))
        print('已创建独立场景：', package)
    else:
        if id not in [p['id'] for p in pages()]:
            raise SystemExit('场景描述不可用')
        if args.action == 'check':
            run(['swift', 'test', '--package-path', str(package)])
            run(['python3', 'scripts/check-boundaries.py', '--page', id])
            run(['python3', 'scripts/check-localization.py', '--page', id])
            run(['swift', 'format', 'lint', '--strict', '--recursive', str(package)])
            if (package / 'Tests/AudioPipelineTests').is_dir():
                run(['python3', '-m', 'unittest', 'discover', '-s', str(package / 'Tests/AudioPipelineTests')])
        else:
            run(['python3', 'scripts/book-build.py', '--preview', '--pages', id])
            if args.action == 'preview':
                run(['open', str(ROOT / ('build/场景预览-' + id + '.app'))])
