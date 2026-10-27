"""Reloaded-source verification. Run in a new Blender process on the saved .blend."""
import json
import sys
from pathlib import Path

import bpy

arguments = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
out = Path(arguments[0] if arguments else Path(bpy.data.filepath).parent)
required = {'CatIdle','CatWalk','CatSit','CatTurn'}
missing = required - set(bpy.data.actions.keys())
if missing:
    raise RuntimeError('保存后缺少动作：'+','.join(sorted(missing)))
rig = bpy.data.objects['ForestCat']
mesh = bpy.data.objects['ForestCatMesh']
if mesh.parent != rig or not any(m.type=='ARMATURE' and m.object==rig for m in mesh.modifiers):
    raise RuntimeError('角色蒙皮关联未保存。')
external = [image.filepath for image in bpy.data.images if image.source=='FILE' and not image.packed_file]
if external or bpy.data.libraries:
    raise RuntimeError('候选源包含未打包的外部文件。')
if Path(bpy.path.abspath(bpy.context.scene.render.filepath)).resolve().parent != out.resolve():
    raise RuntimeError('预览路径越出候选目录。')
if not (out/'candidate.png').is_file():
    raise RuntimeError('预览图片未实际生成。')
if not bpy.context.scene.render.filepath.startswith('//'):
    raise RuntimeError('预览输出不是源文件相对路径。')
curve_counts = {}
for name in sorted(required):
    action = bpy.data.actions[name]
    count = sum(len(bag.fcurves) for layer in action.layers for strip in layer.strips for bag in strip.channelbags)
    if count == 0 or tuple(action.frame_range) != (1.0,49.0):
        raise RuntimeError('动作片段为空或范围错误：'+name)
    curve_counts[name] = count
manifest = json.loads((out/'candidate-manifest.json').read_text())
if not all(row['ground_clearance_passed'] for row in manifest['foot_audit'].values()):
    raise RuntimeError('源足底验证未通过。')
result = {'passed':True,'bones':len(rig.data.bones),'vertices':len(mesh.data.vertices),
          'saved_actions':curve_counts,'external_images':external,'relative_preview_path':bpy.context.scene.render.filepath,
          'note':'新进程重开源文件验证；不等于实际应用中的足底或审美验收。'}
(out/'source-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps(result,ensure_ascii=False,indent=2))
