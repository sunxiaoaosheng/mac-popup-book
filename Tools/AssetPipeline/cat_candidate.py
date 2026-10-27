"""Self-authored orange/cream cat candidate. No external model or paid service.

Use only in an isolated Blender background process. Output remains in build/.
This is a visual/rig candidate, not the approved production replacement.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

arguments = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
out = Path(arguments[0] if arguments else Path(__file__).resolve().parents[2] / 'build/cat-candidate')
out.mkdir(parents=True, exist_ok=True)
scene = bpy.context.scene
for obj in list(scene.objects):
    obj.hide_render = True
    obj.hide_set(True)
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
scene.render.fps = 24
scene.frame_start, scene.frame_end = 1, 49


def color(hexcode):
    rgb = [(hexcode >> shift & 255) / 255 for shift in (16, 8, 0)]
    return tuple(c / 12.92 if c < 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb) + (1,)


def material(name, hexcode, roughness=0.72):
    result = bpy.data.materials.new(name)
    result.diffuse_color = color(hexcode)
    if result.node_tree is None: result.use_nodes = True
    shader = next(n for n in result.node_tree.nodes if n.bl_idname == 'ShaderNodeBsdfPrincipled')
    shader.inputs['Base Color'].default_value = result.diffuse_color
    shader.inputs['Roughness'].default_value = roughness
    return result


orange = material('CatWarmOrange', 0xCC8852)
cream = material('CatCream', 0xF5E9D0)
pink = material('CatSoftPink', 0xD39A8A)
ink = material('CatWarmInk', 0x3A312A, 0.28)
stripe = material('CatQuietStripe', 0xA76B40)
parts = []


def finish(obj, name, mat, bone):
    obj.name = name
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    for poly in obj.data.polygons:
        poly.use_smooth = True
    parts.append(obj)
    obj.select_set(False)
    return obj


def sphere(name, location, scale, mat, bone, segments=24, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=location)
    obj = bpy.context.object
    obj.scale = scale
    return finish(obj, name, mat, bone)


def segment(name, a, b, radius, mat, bone):
    a, b = Vector(a), Vector(b)
    obj = sphere(name, (a+b)/2, (radius, radius, (b-a).length/2+radius*0.6), mat, bone, 16, 10)
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = (b-a).to_track_quat('Z', 'Y')
    return obj


def ear(side):
    vertices = [(side*.09,-.35,1.00),(side*.31,-.25,.97),(side*.27,-.31,1.22),
                (side*.09,-.28,1.00),(side*.31,-.18,.97),(side*.27,-.24,1.22)]
    mesh = bpy.data.meshes.new('EarShell')
    mesh.from_pydata(vertices,[],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)])
    mesh.update()
    obj = bpy.data.objects.new('Ear',mesh)
    scene.collection.objects.link(obj)
    finish(obj,'CatEarLeft' if side<0 else 'CatEarRight',orange,'head')
    # An inset triangular ear, rather than a separate pink button.
    base = [Vector(v) for v in vertices[:3]]
    front = [base[0]*.6+base[1]*.25+base[2]*.15,
             base[0]*.2+base[1]*.65+base[2]*.15,
             base[0]*.15+base[1]*.15+base[2]*.7]
    for v in front: v.y -= .007
    verts = [tuple(v) for v in front] + [tuple(v+Vector((0,.008,0))) for v in front]
    data = bpy.data.meshes.new('EarInnerGeometry')
    data.from_pydata(verts, [], [(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)])
    data.update()
    inside = bpy.data.objects.new('EarInner',data)
    scene.collection.objects.link(inside)
    finish(inside,'CatEarInner',pink,'head')



# Forward is -Y in the authoring scene, converted and validated during export.
sphere('CatBody',(0,.06,.46),(.25,.36,.29),orange,'body')
sphere('CatChest',(0,-.245,.48),(.165,.07,.22),cream,'body')
sphere('CatHead',(0,-.32,.82),(.30,.265,.265),orange,'head')
sphere('CatMuzzle',(0,-.55,.745),(.205,.065,.115),cream,'head')
for side in (-1,1):
    ear(side)
    sphere('CatEye',(side*.112,-.55,.845),(.038,.028,.052),ink,'head',20,12)
    sphere('CatEyeGlint',(side*.112-.009,-.577,.862),(.009,.005,.013),cream,'head',12,8)
    sphere('CatCheek',(side*.17,-.556,.758),(.055,.022,.033),cream,'head',16,8)
    segment('CatFrontLeg',(side*.145,-.205,.42),(side*.145,-.14,.23),.075,orange,'front.'+str(side))
    sphere('CatFrontPaw',(side*.145,-.285,.105),(.079,.115,.095),cream,'foot.'+str(side),20,10)
    segment('CatFrontShin',(side*.145,-.14,.23),(side*.145,-.285,.105),.055,orange,'paw.'+str(side))
    sphere('CatHaunch',(side*.18,.225,.29),(.13,.16,.19),orange,'hind.'+str(side))
    sphere('CatHindPaw',(side*.18,.15,.08),(.09,.13,.07),cream,'backfoot.'+str(side),20,10)
    segment('CatHindShin',(side*.18,.36,.21),(side*.18,.15,.08),.065,orange,'backpaw.'+str(side))
sphere('CatNose',(0,-.613,.79),(.03,.014,.021),pink,'head',16,10)
# A small sculpted smile, joined into the skinned head mesh.
curve = bpy.data.curves.new('CatSmileCurve','CURVE')
curve.dimensions='3D'
curve.bevel_depth=.0035
curve.bevel_resolution=2
spline=curve.splines.new('POLY')
smile=[(-.045,-.611,.754),(-.023,-.617,.745),(0,-.619,.754),(.023,-.617,.745),(.045,-.611,.754)]
spline.points.add(len(smile)-1)
for point,xyz in zip(spline.points,smile): point.co=(*xyz,1)
obj=bpy.data.objects.new('CatSmile',curve)
scene.collection.objects.link(obj)
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active=obj
bpy.ops.object.convert(target='MESH')
finish(bpy.context.object,'CatSmile',ink,'head')
for x in (-.09,0,.09):
    sphere('CatForeheadStripe',(x,-.513,.994),(.019,.012,.054),stripe,'head',12,8)
# Continuous curved tail with smoothly varying weights over its two joints.
curve=bpy.data.curves.new('CatTailCurve','CURVE')
curve.dimensions='3D'
curve.resolution_u=12
curve.bevel_depth=.06
curve.bevel_resolution=3
curve.use_fill_caps=True
spline=curve.splines.new('BEZIER')
points=[(0,.31,.46),(.04,.49,.52),(.16,.61,.67),(.29,.63,.84),(.34,.56,.96),(.28,.48,1.00)]
spline.bezier_points.add(len(points)-1)
for point,xyz in zip(spline.bezier_points,points):
    point.co=xyz
    point.handle_left_type=point.handle_right_type='AUTO'
obj=bpy.data.objects.new('CatTail',curve)
scene.collection.objects.link(obj)
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active=obj
bpy.ops.object.convert(target='MESH')
tail=finish(bpy.context.object,'CatTail',orange,'tail.base')
tip_group=tail.vertex_groups.new(name='tail.tip')
for vertex in tail.data.vertices:
    z=(tail.matrix_world@vertex.co).z
    weight=max(0,min(1,(z-.58)/.24))
    tail.vertex_groups['tail.base'].add([vertex.index],1-weight,'REPLACE')
    tip_group.add([vertex.index],weight,'REPLACE')
sphere('CatTailTip',points[-1],(.06,.06,.06),cream,'tail.tip',20,12)

bpy.ops.object.select_all(action='DESELECT')
for obj in parts: obj.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.object.join()
mesh=bpy.context.object
mesh.name='ForestCatMesh'
mesh.data.name='ForestCatGeometry'
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.object.armature_add(enter_editmode=True,location=(0,0,0))
rig=bpy.context.object
rig.name='ForestCat'
rig.data.name='ForestCatSkeleton'
root=rig.data.edit_bones[0]
root.name='root'
root.head,root.tail=(0,0,.04),(0,0,.44)


def bone(name,head,tail,parent):
    node=rig.data.edit_bones.new(name)
    node.head,node.tail=head,tail
    node.parent=rig.data.edit_bones[parent]


bone('body',(0,.08,.44),(0,-.18,.59),'root')
bone('head',(0,-.22,.6),(0,-.35,.94),'body')
for side in (-1,1):
    bone('front.'+str(side),(side*.145,-.205,.43),(side*.145,-.14,.23),'body')
    bone('paw.'+str(side),(side*.145,-.14,.23),(side*.145,-.285,.105),'front.'+str(side))
    bone('foot.'+str(side),(side*.145,-.285,.105),(side*.145,-.38,.105),'paw.'+str(side))
    bone('hind.'+str(side),(side*.18,.23,.4),(side*.18,.36,.21),'body')
    bone('backpaw.'+str(side),(side*.18,.36,.21),(side*.18,.15,.08),'hind.'+str(side))
    bone('backfoot.'+str(side),(side*.18,.15,.08),(side*.18,.03,.08),'backpaw.'+str(side))
bone('tail.base',(0,.31,.46),(.16,.61,.67),'body')
bone('tail.tip',(.16,.61,.67),(.32,.53,.98),'tail.base')
bpy.ops.object.mode_set(mode='OBJECT')
modifier=mesh.modifiers.new('ForestCatSkin','ARMATURE')
modifier.object=rig
mesh.parent=rig
rig.animation_data_create()


sys.path.insert(0,str(Path(__file__).resolve().parent))
from cat_motion import build_clips, audit_feet, CLIPS
controls, bake_errors = build_clips(rig,scene)
foot_audit = audit_feet(rig,mesh,scene,controls)
if not all(row['ground_clearance_passed'] for row in foot_audit.values()):
    raise RuntimeError('候选动作足底检查未通过，停止导出。')

for name in CLIPS:
    rig.animation_data.action=bpy.data.actions[name]
    scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    mesh.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.wm.usd_export(filepath=str(out/(name+'.usdz')), selected_objects_only=True,
        export_animation=True,export_armatures=True,only_deform_bones=True,export_materials=True,
        convert_orientation=True,export_global_forward_selection='NEGATIVE_Z',export_global_up_selection='Y')
rig.animation_data.action=bpy.data.actions['CatIdle']
scene.frame_set(1)
bpy.context.view_layer.update()

# Preview camera, floor and lighting are excluded from character exports.
rig.select_set(False)
mesh.select_set(False)
floor_mat=material('PreviewCreamPaper',0xF7F0DE)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,0))
floor=bpy.context.object
floor.name='PreviewFloor'
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(2.2,-3.5,1.9))
camera=bpy.context.object
camera.name='PreviewCamera'
camera.rotation_euler=(Vector((0,-.02,.60))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO'
camera.data.ortho_scale=1.9
scene.camera=camera
for name,location,energy,size in [('PreviewKey',(2,-3,4),350,4),('PreviewFill',(-3,-1,2),150,3),('PreviewRim',(0,3,3),250,3)]:
    bpy.ops.object.light_add(type='AREA',location=location)
    light=bpy.context.object
    light.name=name
    light.data.energy=energy
    light.data.shape='DISK'
    light.data.size=size
    light.rotation_euler=(Vector((0,0,.5))-light.location).to_track_quat('-Z','Y').to_euler()
if scene.world.node_tree is None: scene.world.use_nodes=True
background=next(n for n in scene.world.node_tree.nodes if n.bl_idname=='ShaderNodeBackground')
background.inputs['Color'].default_value=(0.7,0.75,0.8,1)
background.inputs['Strength'].default_value=.35
scene.render.engine='BLENDER_EEVEE'
scene.render.resolution_x=768
scene.render.resolution_y=768
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
scene.render.filepath='//candidate.png'
bpy.ops.wm.save_as_mainfile(filepath=str(out/'ForestCatCandidate.blend'), relative_remap=False)
result={'status':'未定稿的自有三维候选，未替换默认纸猫', 'source':'Blender脚本自制，无外部模型',
        'bones':len(rig.data.bones),'vertices':len(mesh.data.vertices),'actions':list(CLIPS),'bake_max_errors':bake_errors,'foot_audit':foot_audit,
        'note':'CatTurn为原地步态，整体朝向由运行表现控制；坐下/走路尚需足底与变形验收。'}
(out/'candidate-manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
bpy.ops.render.render(write_still=True)
