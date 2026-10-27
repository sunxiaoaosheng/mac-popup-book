"""Build a small skin/animation import probe in an isolated Blender file.

Run against build/asset-preflight/seed.blend. This is not a final cat model.
Set PROBE_OUTPUT to an absolute ignored output directory before executing.
"""
import json
from pathlib import Path

import bpy

if 'PROBE_OUTPUT' not in globals():
    import sys
    arguments = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    PROBE_OUTPUT = arguments[0] if arguments else str(Path(__file__).resolve().parents[2] / 'build/asset-preflight')
out = Path(PROBE_OUTPUT)
out.mkdir(parents=True, exist_ok=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.render.fps = 24
scene.frame_start, scene.frame_end = 1, 49
bpy.ops.object.select_all(action='DESELECT')

# Work only on newly-created data; the factory seed and any existing objects remain intact.
bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.35, location=(0, 0, 1))
mesh = bpy.context.object
mesh.name = 'ProbeMesh'
mesh.scale = (1, 1, 2)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
material = bpy.data.materials.new('ProbeWarmPaper')
material.diffuse_color = (0.65, 0.33, 0.13, 1)
if material.node_tree is None: material.use_nodes = True
shader = next(n for n in material.node_tree.nodes if n.bl_idname == 'ShaderNodeBsdfPrincipled')
shader.inputs['Base Color'].default_value = material.diffuse_color
shader.inputs['Roughness'].default_value = 0.85
mesh.data.materials.append(material)
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
rig = bpy.context.object
rig.name = 'ProbeRig'
rig.data.name = 'ProbeSkeleton'
base = rig.data.edit_bones[0]
base.name = 'root'
base.head, base.tail = (0, 0, 0.3), (0, 0, 1)
tip = rig.data.edit_bones.new('tip')
tip.head, tip.tail = (0, 0, 1), (0, 0, 1.7)
tip.parent, tip.use_connect = base, True
bpy.ops.object.mode_set(mode='OBJECT')
root_group = mesh.vertex_groups.new(name='root')
tip_group = mesh.vertex_groups.new(name='tip')
for vertex in mesh.data.vertices:
    z = (mesh.matrix_world @ vertex.co).z
    weight = max(0, min(1, (z - 0.8) / 0.4))
    root_group.add([vertex.index], 1-weight, 'REPLACE')
    tip_group.add([vertex.index], weight, 'REPLACE')
modifier = mesh.modifiers.new('ProbeSkin', 'ARMATURE')
modifier.object = rig
mesh.parent = rig
bone = rig.pose.bones['tip']
bone.rotation_mode = 'XYZ'
for frame, angle in [(1, 0), (13, 0.35), (25, 0), (37, -0.35), (49, 0)]:
    bone.rotation_euler[1] = angle
    bone.keyframe_insert(data_path='rotation_euler', frame=frame)
rig.animation_data.action.name = 'ProbeSway'
scene.frame_set(1)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
mesh.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.wm.save_as_mainfile(filepath=str(out / 'rig-probe.blend'))
bpy.ops.wm.usd_export(filepath=str(out / 'rig-probe.usdz'), selected_objects_only=True,
                      export_animation=True, export_armatures=True, only_deform_bones=True,
                      export_materials=True, convert_orientation=True,
                      export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y')
bpy.ops.export_scene.gltf(filepath=str(out / 'rig-probe.glb'), export_format='GLB',
                          use_selection=True, export_animations=True, export_skins=True)
result = {
    'kind': '骨骼与动作导入预检，不是正式猫资产',
    'blender': bpy.app.version_string,
    'bones': [b.name for b in rig.data.bones],
    'actions': [a.name for a in bpy.data.actions],
    'vertices': len(mesh.data.vertices),
    'files': {p.name: p.stat().st_size for p in out.iterdir() if p.name.startswith('rig-probe.')},
}
(out / 'probe-manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
