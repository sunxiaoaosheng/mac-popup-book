"""Cat candidate foot controls and baked FK clips. Authoring-only Blender module."""
import math

import bpy
from mathutils import Vector

CLIPS = ('CatIdle', 'CatWalk', 'CatSit', 'CatTurn')


def linear_keys(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'


def make_controls(rig):
    controls = {}
    constraints = []
    for side in (-1, 1):
        for family, ankle, foot in [('front', 'paw', 'foot'), ('hind', 'backpaw', 'backfoot')]:
            key = family + '.' + str(side)
            foot_name = foot + '.' + str(side)
            pb = rig.pose.bones[foot_name]
            target = bpy.data.objects.new('FootControl.' + key, None)
            bpy.context.scene.collection.objects.link(target)
            target.parent = rig
            target.location = pb.bone.head_local
            target.rotation_mode = 'QUATERNION'
            target.rotation_quaternion = pb.bone.matrix_local.to_quaternion()
            target.empty_display_type = 'SPHERE'
            target.empty_display_size = .025
            lower = rig.pose.bones[ankle + '.' + str(side)]
            ik = lower.constraints.new('IK')
            ik.name = 'FootPlantIK'
            ik.target = target
            ik.chain_count = 2
            ik.use_tail = True
            ik.use_stretch = False
            rotation = pb.constraints.new('COPY_ROTATION')
            rotation.name = 'KeepPawLevel'
            rotation.target = target
            rotation.owner_space = rotation.target_space = 'WORLD'
            controls[key] = (target, pb.bone.head_local.copy(), foot_name)
            constraints += [ik, rotation]
    return controls, constraints


def foot_path(clip, key, u):
    side = -1 if key.endswith('-1') else 1
    diagonal = (key.startswith('front') and side == -1) or (key.startswith('hind') and side == 1)
    phase = (u + (0 if diagonal else .5)) % 1
    if clip not in ('CatWalk', 'CatTurn'):
        return 0, 0, True
    stride = .14 if clip == 'CatWalk' else .04
    lift = .055 if clip == 'CatWalk' else .025
    if phase < .6:
        return -stride / 2 + stride * phase / .6, 0, True
    swing = (phase - .6) / .4
    return stride / 2 - stride * swing, lift * math.sin(math.pi * swing), False


def source_clip(rig, controls, constraints, clip):
    for constraint in constraints:
        constraint.mute = False
    action = bpy.data.actions.new('Source_' + clip)
    action.use_fake_user = True
    rig.animation_data.action = action
    for key, (target, _, _) in controls.items():
        target.animation_data_create()
        target.animation_data.action = bpy.data.actions.new('Source_' + clip + '.Foot.' + key)
        target.animation_data.action.use_fake_user = True
    for frame in range(1, 50):
        u = (frame - 1) / 48
        phase = 2 * math.pi * u
        for pb in rig.pose.bones:
            pb.rotation_mode = 'XYZ'
            pb.rotation_euler = (0, 0, 0)
            pb.location = (0, 0, 0)
            pb.scale = (1, 1, 1)
        body, head = rig.pose.bones['body'], rig.pose.bones['head']
        rise = .005 * math.sin(phase)
        head.rotation_euler[2] = .018 * math.sin(phase)
        rig.pose.bones['tail.tip'].rotation_euler[0] = .09 * math.sin(phase)
        if clip == 'CatWalk':
            rise = .012 * (1 - math.cos(2 * phase))
        elif clip == 'CatSit':
            rise = -.07 * u * u * (3 - 2 * u)
        elif clip == 'CatTurn':
            body.rotation_euler[2] = .08 * math.sin(phase)
            head.rotation_euler[2] = .16 * math.sin(phase)
        body.location = body.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, rise))
        for key, (target, rest, _) in controls.items():
            y, z, _ = foot_path(clip, key, u)
            target.location = rest + Vector((0, y, z))
            target.keyframe_insert(data_path='location', frame=frame)
        for pb in rig.pose.bones:
            pb.keyframe_insert(data_path='rotation_euler', frame=frame)
            pb.keyframe_insert(data_path='location', frame=frame)
    linear_keys(action)
    for target, _, _ in controls.values():
        linear_keys(target.animation_data.action)


def bake_clip(rig, constraints, scene, clip):
    samples = {}
    for frame in range(1, 50):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        evaluated = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        samples[frame] = {pb.name: pb.matrix.copy() for pb in evaluated.pose.bones}
    for constraint in constraints:
        constraint.mute = True
    action = bpy.data.actions.new(clip)
    action.use_fake_user = True
    rig.animation_data.action = action
    for frame, matrices in samples.items():
        for pb in rig.pose.bones:
            options = {}
            if pb.parent:
                options = {'parent_matrix': matrices[pb.parent.name],
                           'parent_matrix_local': pb.parent.bone.matrix_local}
            pb.rotation_mode = 'QUATERNION'
            pb.matrix_basis = pb.bone.convert_local_to_pose(matrices[pb.name], pb.bone.matrix_local,
                                                          invert=True, **options)
            for path in ('location', 'rotation_quaternion', 'scale'):
                pb.keyframe_insert(data_path=path, frame=frame)
    linear_keys(action)
    maximum = 0
    for frame, expected in samples.items():
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        evaluated = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        for pb in evaluated.pose.bones:
            maximum = max(maximum, max(abs(pb.matrix[row][column] - expected[pb.name][row][column])
                                      for row in range(4) for column in range(4)))
    if maximum > .0001:
        raise RuntimeError('动作烘焙未保持骨骼姿态：' + clip + ' error=' + str(maximum))
    return maximum


def build_clips(rig, scene):
    controls, constraints = make_controls(rig)
    errors = {}
    for clip in CLIPS:
        source_clip(rig, controls, constraints, clip)
        errors[clip] = bake_clip(rig, constraints, scene, clip)
    rig.animation_data.action = bpy.data.actions['CatIdle']
    scene.frame_set(1)
    rig['authoring_note'] = '运行使用Cat*烘焙动作。Source_*和FootControl为可编辑足控源，编辑源需启用IK约束。'
    return controls, errors


def audit_feet(rig, mesh, scene, controls):
    indices = {}
    for key, (_, _, foot_name) in controls.items():
        group = mesh.vertex_groups[foot_name].index
        indices[key] = [v.index for v in mesh.data.vertices if any(g.group == group and g.weight > .9 for g in v.groups)]
    report = {}
    for clip in CLIPS:
        rig.animation_data.action = bpy.data.actions[clip]
        min_z, max_stance_z = 100, -100
        for frame in range(1, 50):
            scene.frame_set(frame)
            graph = bpy.context.evaluated_depsgraph_get()
            evaluated = mesh.evaluated_get(graph)
            geometry = evaluated.to_mesh()
            for key, vertices in indices.items():
                z = min((evaluated.matrix_world @ geometry.vertices[index].co).z for index in vertices)
                min_z = min(min_z, z)
                if foot_path(clip, key, (frame-1)/48)[2]:
                    max_stance_z = max(max_stance_z, z)
            evaluated.to_mesh_clear()
        report[clip] = {'minimum_foot_z': min_z, 'maximum_stance_foot_z': max_stance_z,
                        'ground_clearance_passed': min_z >= -.005 and max_stance_z <= .03}
    rig.animation_data.action = bpy.data.actions['CatIdle']
    scene.frame_set(1)
    return report
