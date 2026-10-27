#!/usr/bin/env python3
"""Fingerprint local source and signed output after a build; Git is optional."""
import datetime
import hashlib
import json
import pathlib
import os
import plistlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / 'build/林间小屋.app'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    sources = []
    for folder in ['Modules', 'Apps', 'Scenes', 'Templates', 'Book', 'Experiments', 'Tests', 'Tools', 'scripts', '.github', '.cursor']:
        for directory, names, files in os.walk(ROOT / folder):
            names[:] = [name for name in names if name not in {'.build', '.git', '.swiftpm', '__pycache__', 'build', 'artifacts', 'logs'}]
            sources += [pathlib.Path(directory) / name for name in files if name != '.DS_Store']
    sources += [ROOT / name for name in ['Package.swift', 'README.md', 'AGENTS.md', '.swift-format', '.gitignore']
                if (ROOT / name).is_file()]
    manifest = {}
    for path in sorted(sources):
        if path.is_symlink():
            raise ValueError('构建凭据不接受工程源文件的外部链接：' + str(path.relative_to(ROOT)))
        manifest[str(path.relative_to(ROOT))] = digest(path)
    source_hash = hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()
    info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    executable = APP / 'Contents/MacOS' / info['CFBundleExecutable']
    application_files = {}
    for path in sorted(APP.rglob('*')):
        if path.is_file():
            if path.is_symlink():
                raise ValueError('应用产物包含未经核对的符号链接：' + str(path.relative_to(APP)))
            application_files[str(path.relative_to(APP))] = digest(path)
    application_hash = hashlib.sha256(json.dumps(application_files, sort_keys=True).encode()).hexdigest()
    git = None
    if (ROOT / '.git').exists():
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        status = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True)
        git = {'base_revision': revision, 'has_worktree_changes': bool(status.strip())}
    receipt = {
        'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'configuration': 'Release', 'bundle_identifier': info['CFBundleIdentifier'],
        'application_version': info['CFBundleShortVersionString'],
        'executable_sha256': digest(executable), 'source_manifest_sha256': source_hash,
        'application_manifest_sha256': application_hash, 'application_files': application_files,
        'source_files': manifest, 'git': git,
        'scope': '本地构建与源码对应凭据；不代表已提交、已发布、物理输入或体验验收通过',
    }
    output = ROOT / 'build/build-receipt.json'
    temporary = output.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+'\n')
    temporary.replace(output)
    print('已记录本地构建凭据：' + str(output))


if __name__ == '__main__':
    main()
