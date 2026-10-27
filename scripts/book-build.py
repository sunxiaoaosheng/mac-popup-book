#!/usr/bin/env python3
"""Build the host and selected independent page packages, then sign each service inside-out."""
import argparse, json, pathlib, plistlib, shutil, subprocess, uuid
ROOT = pathlib.Path(__file__).resolve().parents[1]

def command(args, cwd=ROOT):
    subprocess.run(args, cwd=cwd, check=True)

def binary_path(package):
    return pathlib.Path(subprocess.check_output(['swift', 'build', '--package-path', str(package), '-c', 'release', '--show-bin-path'], text=True).strip())

def build(args):
    published = json.loads((ROOT / 'Book/published-pages.json').read_text())
    ids = args.pages.split(',') if args.pages else published['pages']
    descriptors = []
    for id in ids:
        if not id or any((c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in id)):
            raise ValueError('无效页面标识')
        package = ROOT / 'Scenes' / id
        page = json.loads((package / 'page.json').read_text())
        assert page['id'] == id and page['contractVersion'] == 1
        command(['swift', 'build', '--package-path', str(package), '-c', 'release', '--product', page['product']])
        descriptors.append((package, page, binary_path(package)))
    host_product = 'BookIntegrationCheck' if args.background_check else 'ForestBook'
    command(['swift', 'build', '-c', 'release', '--product', host_product])
    bin = binary_path(ROOT)
    name = ('后台验收-' if args.background_check else '场景预览-') + (ids[0] if len(ids) == 1 else 'integration') + '.app' if args.preview else '林间小屋.app'
    target = ROOT / 'build' / name
    stage = ROOT / 'build' / ('book-stage-' + uuid.uuid4().hex + '.app')
    contents = stage / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    resources = contents / 'Resources'
    resources.mkdir()
    shutil.copy2(bin / host_product, contents / 'MacOS' / host_product)
    info = plistlib.loads((ROOT / 'Apps/ForestCabin/Resources/Info.plist').read_bytes())
    if args.preview:
        info['CFBundleIdentifier'] = 'local.ssr.popupbook.preview.' + (ids[0] if len(ids) == 1 else 'integration')
    info['BookPreview'] = args.preview
    info['CFBundleExecutable'] = host_product
    if args.background_check:
        info['CFBundleIdentifier'] += '.background-check'
        info['LSBackgroundOnly'] = True
    info['CFBundleShortVersionString'] = '0.2.0'
    info['CFBundleVersion'] = '3'
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    for path in bin.glob('*.bundle'):
        shutil.copytree(path, resources / path.name)
    shutil.copy2(ROOT / 'Apps/ForestCabin/Resources/AppIcon.icns', resources / 'AppIcon.icns')
    for lang in ['en', 'zh-Hans']:
        shutil.copytree(ROOT / f'Apps/ForestCabin/Resources/{lang}.lproj', resources / f'{lang}.lproj')
    (resources / 'Pages').mkdir()
    (resources / 'published-pages.json').write_text(json.dumps({'version': 1, 'pages': ids}))
    for (package, page, worker_bin) in descriptors:
        service = contents / 'XPCServices' / (page['id'] + '.xpc')
        worker = service / 'Contents/MacOS'
        worker.mkdir(parents=True)
        shutil.copy2(worker_bin / page['product'], worker / page['product'])
        service_resources = service / 'Contents/Resources'
        service_resources.mkdir()
        for path in worker_bin.glob('*.bundle'):
            shutil.copytree(path, service_resources / path.name)
        for path in (package / 'Resources').glob('*'):
            if path.is_dir():
                shutil.copytree(path, service_resources / path.name)
            else:
                shutil.copy2(path, service_resources / path.name)
        for asset in page['audio']:
            resource = service_resources / asset['path']
            if '..' in pathlib.PurePosixPath(asset['path']).parts or not resource.is_file():
                raise ValueError('缺少或非法声音资源：' + asset['path'])
        service_info = dict(CFBundleIdentifier=page['service'], CFBundleExecutable=page['product'], CFBundlePackageType='XPC!', XPCService=dict(ServiceType='Application', RunLoopType='NSRunLoop'), BookTestService=bool(args.preview and page.get('testOnly', False)))
        (service / 'Contents/Info.plist').write_bytes(plistlib.dumps(service_info))
        (resources / 'Pages' / (page['id'] + '.json')).write_text(json.dumps(page, ensure_ascii=False))
        command(['codesign', '--force', '--sign', '-', str(service)])
    command(['codesign', '--force', '--sign', '-', str(stage)])
    command(['codesign', '--verify', '--deep', '--strict', str(stage)])
    baseline = ROOT / 'build/baseline-林间小屋.app'
    if target.exists():
        if not args.preview and (not baseline.exists()):
            shutil.copytree(target, baseline)
        shutil.rmtree(target)
    stage.rename(target)
    if not args.preview:
        command(['python3', 'scripts/write-build-receipt.py'])
    print('已构建独立进程整书：', target, flush=True)
if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--pages')
    parser.add_argument('--preview', action='store_true')
    parser.add_argument('--background-check', action='store_true')
    args = parser.parse_args()
    if args.background_check:
        args.preview = True
    build(args)
