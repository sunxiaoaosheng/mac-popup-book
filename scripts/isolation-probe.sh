#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --package-path Tools/IsolationProbe -c release
BIN="$(swift build --package-path Tools/IsolationProbe -c release --show-bin-path)"
export PROBE_BIN="$BIN" PROBE_ROOT="$PWD"
python3 - <<'PY'
import os,pathlib,plistlib,shutil,subprocess
root=pathlib.Path(os.environ['PROBE_ROOT']);binary=pathlib.Path(os.environ['PROBE_BIN'])
app=root/'build/进程隔离样件.app'; contents=app/'Contents'
(contents/'MacOS').mkdir(parents=True,exist_ok=True)
shutil.copy2(binary/'ProbeHost',contents/'MacOS/ProbeHost')
(contents/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.ssr.isolation-probe',CFBundleExecutable='ProbeHost',CFBundleName='进程隔离样件',CFBundlePackageType='APPL',NSHighResolutionCapable=True)))
for name in ['red','blue']:
 service=contents/'XPCServices'/f'{name}.xpc';(service/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
 shutil.copy2(binary/'ProbeWorker',service/'Contents/MacOS/ProbeWorker')
 (service/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.ssr.isolation-probe.'+name,CFBundleExecutable='ProbeWorker',CFBundlePackageType='XPC!',XPCService=dict(ServiceType='Application',RunLoopType='NSRunLoop'))))
 subprocess.run(['codesign','--force','--sign','-',str(service)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
PY
"$PWD/build/进程隔离样件.app/Contents/MacOS/ProbeHost" "${@:-}"
