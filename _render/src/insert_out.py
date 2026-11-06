
# ---- INSERT_OUT (Vu, Nov 6): return clip. The bank starts FULLY OUTSIDE the kiosk (clear of the slot),
# glides in, lines up with the empty slot and is pushed in until it clicks. Run AFTER setup_back.py:
#   Blender -b _vert/kiosk_vert.blend --python _vert/setup_back.py --python _vert/insert_out.py -o _vert/seq38/f_#### -s 440 -e 506 -a
# The eject clip (bank inside -> pops out) is unchanged (seq37 / eject2.mp4).
import bpy, math
from mathutils import Vector, Quaternion
from bpy_extras.object_utils import world_to_camera_view
sc=bpy.context.scene; vl=bpy.context.view_layer
F0=440; N=66
AZ_DEG=-4; EL_DEG=20; LENS=40.0; FILL=0.86                     # clip = frames 440..506 (67 frames @30 fps)
def T(t): return F0+t
pb=bpy.data.objects['PowerBank']
cam=sc.camera; cd=cam.data; tgt=bpy.data.objects.get('Cam_Target')

# 1) freeze camera at the eject clip's last framing (frame 488), then widen it so the whole bank fits
sc.frame_set(488); vl.update()
CL=cam.location.copy(); TL=tgt.location.copy() if tgt else None
lens=cd.lens; sx=cd.shift_x; sy=cd.shift_y; fs=cd.dof.aperture_fstop
for idb in (cam,cd,tgt):
    if idb and idb.animation_data: idb.animation_data_clear()
cam.location=CL
if tgt: tgt.location=TL
cd.lens=lens; cd.shift_x=sx; cd.shift_y=sy; cd.dof.aperture_fstop=fs

# 2) bank keys
Q0=Quaternion((0.5,0.5,-0.5,0.5)); X0,Z0=0.2395,0.66
Y_IN=0.0255; Y_ALIGN=-0.112; Y_START=-0.175      # kiosk face y=-0.03, bank half length ~0.072
QS=Quaternion((0,0,1),math.radians(-7))@Quaternion((1,0,0),math.radians(-4))@Q0
poses=[ (0,  (X0-0.004,Y_START,Z0+0.016),QS),
        (6,  (X0-0.0035,Y_START+0.004,Z0+0.014),QS.slerp(Q0,0.08)),
        (24, (X0,Y_ALIGN,Z0),Q0),
        (28, (X0,Y_ALIGN+0.004,Z0),Q0),
        (47, (X0,Y_IN+0.0018,Z0),Q0),     # pushed a hair past home ...
        (51, (X0,Y_IN,Z0),Q0),            # ... and it clicks back into place
        (N,  (X0,Y_IN,Z0),Q0)]
pb.animation_data_clear(); pb.rotation_mode='QUATERNION'; pb.scale=(1,1,1)
for t,loc,q in poses:
    pb.location=loc; pb.rotation_quaternion=q
    pb.keyframe_insert('location',frame=T(t)); pb.keyframe_insert('rotation_quaternion',frame=T(t))
for fc in pb.animation_data.action.fcurves:
    for k in fc.keyframe_points:
        k.interpolation='BEZIER'; k.handle_left_type='AUTO_CLAMPED'; k.handle_right_type='AUTO_CLAMPED'
    fc.update()

# 3) slot status light: blinks while waiting, solid once locked
st=bpy.data.objects.get('Ins_Status_123')
if st:
    st.animation_data_clear()
    for t in range(0,47,7):
        for v in (1.0,0.12):
            st.color=(v,v,v,1); st.keyframe_insert('color',frame=T(t+(0 if v==1.0 else 3.5)))
    st.color=(1,1,1,1); st.keyframe_insert('color',frame=T(47)); st.keyframe_insert('color',frame=T(N))
    for fc in st.animation_data.action.fcurves:
        for k in fc.keyframe_points: k.interpolation='CONSTANT'
cv=bpy.data.objects.get('Ins_Cover_123')
if cv: cv.animation_data_clear(); cv.scale=(1,1,0.0001)

# 4) phone is not part of this shot
pr=bpy.data.objects.get('PhoneRig')
if pr:
    for o in [pr]+list(pr.children_recursive): o.hide_render=True

# 5) frame it: same side-front look as the eject clip, a bit more frontal, dolly back (no wide-angle zoom)
#    until the whole bank (start pose) and the slot mouth fit with margin
def bank_pts():
    dg=bpy.context.evaluated_depsgraph_get(); pts=[]
    oe=bpy.data.objects['PB_Body'].evaluated_get(dg); pts+=[oe.matrix_world@Vector(c) for c in oe.bound_box]
    return pts
AZ=math.radians(AZ_DEG); EL=math.radians(EL_DEG)
DIR=Vector((math.cos(EL)*math.cos(AZ),math.cos(EL)*math.sin(AZ),math.sin(EL)))   # target -> camera
cd.lens=LENS; cd.shift_x=0.0; cd.shift_y=0.0; cd.dof.aperture_fstop=128
for c in list(cam.constraints): cam.constraints.remove(c)
cam.rotation_mode='XYZ'; cam.rotation_euler=(-DIR).to_track_quat('-Z','Y').to_euler()
asp=sc.render.resolution_y/sc.render.resolution_x
def centre(t):
    sc.frame_set(T(t)); vl.update(); p=bank_pts(); return sum(p,Vector())/len(p), p
# distance: bank (start pose) + the slot mouth + the kiosk's front edge all fit ~FILL of the frame width
MOUTH=Vector((X0,-0.03,Z0)); EDGE=Vector((0.33,-0.03,Z0))
c0,p0=centre(0); p0=p0+[MOUTH,EDGE]
a0=sum(p0,Vector())/len(p0)
dist=0.5
for it in range(10):
    cam.location=a0+DIR*dist; vl.update()
    P=[world_to_camera_view(sc,cam,q) for q in p0]
    x0=min(p.x for p in P); x1=max(p.x for p in P)
    a0=a0+cam.matrix_world.to_3x3()@Vector(((x0+x1)/2-0.5,0,0))*dist*0.35
    dist*=((x1-x0)/FILL)**0.9
c24,p24=centre(24); a24=sum(p24+[MOUTH,EDGE],Vector())/(len(p24)+2)
aims=[(0,a0,1.0),(8,a0.lerp(a24,0.2),0.99),(24,a24,0.94),(47,a24.lerp(MOUTH,0.6),0.86),(N,a24.lerp(MOUTH,0.65),0.84)]
for t,aim,k in aims:
    cam.location=aim+DIR*dist*k; cam.keyframe_insert('location',frame=T(t))
for fc in cam.animation_data.action.fcurves:
    for kp in fc.keyframe_points: kp.interpolation='BEZIER'; kp.handle_left_type='AUTO_CLAMPED'; kp.handle_right_type='AUTO_CLAMPED'
    fc.update()
C=a0; CAM0=a0+DIR*dist
open('/tmp/cfz_insert_fit.txt','w').write(f"dist {dist:.3f} cam {tuple(round(v,3) for v in CAM0)} tgt {tuple(round(v,3) for v in C)} x[{x0:.2f},{x1:.2f}]")
sc.frame_start=T(0); sc.frame_end=T(N)
