#!/usr/bin/env python3
"""Validate compiled module edges and source imports, without building or reading hardware."""
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
EDGES = {
    "PopupBookCore": set(),
    "PopupBookRuntime": {"PopupBookCore"},
    "MacPlatform": {"PopupBookCore"},
    "SceneKitRendering": {"PopupBookCore"},
    "PaperCatBehavior": {"PopupBookCore"},
    "VolumeCatRendering": {"PopupBookCore", "SceneKitRendering", "PaperCatBehavior"},
    "PaperCatRendering": {"PopupBookCore", "SceneKitRendering", "PaperCatBehavior"},
    "ForestCabinScene": {"PopupBookCore", "SceneKitRendering"},
    "ForestCabinApp": {"PopupBookCore", "PopupBookRuntime", "MacPlatform", "SceneKitRendering", "PaperCatBehavior", "PaperCatRendering", "ForestCabinScene"},
}
FOUNDATION_ONLY = {"PopupBookCore", "PopupBookRuntime", "PaperCatBehavior"}
package = json.loads(subprocess.check_output(["swift", "package", "dump-package"], cwd=ROOT))
errors = []
for target in package["targets"]:
    name = target["name"]
    if name not in EDGES:
        continue
    dependencies = {d.get("byName", d.get("target", [None]))[0] for d in target["dependencies"]}
    if dependencies != EDGES[name]:
        errors.append(f"{name}: 模块依赖不符合约定 {dependencies}")
    for source in (ROOT / target["path"]).rglob("*.swift"):
        text = source.read_text()
        imports = set(re.findall(r"^import (\w+)", text, re.M))
        if name in FOUNDATION_ONLY and not imports <= {"Foundation"} | EDGES[name]:
            errors.append(f"{source.relative_to(ROOT)}: 纯逻辑模块导入平台/表现框架")
        if name in {"PopupBookCore", "PopupBookRuntime", "MacPlatform", "SceneKitRendering"} and re.search(r"\b(?:CatPose|CatMood|PaperCat|ForestCabin)\b", text):
            errors.append(f"{source.relative_to(ROOT)}: 公共模块引用具体内容")
        if re.search(r"/Users/|mac-duo|open_resource_project", text):
            errors.append(f"{source.relative_to(ROOT)}: 存在用户或研究目录依赖")
# UI adapters must not know a concrete character; only composition selects one.
for source in (ROOT / "Apps/ForestCabin/App").glob("*.swift"):
    if source.name != "ForestComposition.swift" and re.search(r"\b(?:PaperCat|CatPose|CatMood|PaperCatPresenter)\b", source.read_text()):
        errors.append(f"{source.relative_to(ROOT)}: 界面依赖具体角色，应移到应用组装")
# Runtime resources belong to the app and must be available without research files.
import plistlib
resource_root = ROOT / "Apps/ForestCabin/Resources"
info = plistlib.loads((resource_root / "Info.plist").read_bytes())
if info.get("CFBundleIdentifier") != "local.ssr.forestbook":
    errors.append("既有应用标识发生变化")
for name in ["paper.wav", "paper-soft.wav", "forest.wav", "meow.wav", "meow-soft.wav", "meow-short.wav",
             "footstep.wav", "footstep-soft.wav", "purr.wav"]:
    data = (resource_root / "Audio" / name).read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        errors.append("无效音效资源：" + name)
if not (resource_root / "AppIcon.icns").is_file():
    errors.append("缺少应用图标")
if errors:
    raise SystemExit("\n".join(errors))
print("模块依赖、纯逻辑导入和独立路径检查通过。")
