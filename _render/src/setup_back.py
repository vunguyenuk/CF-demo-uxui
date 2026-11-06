
import bpy, mathutils
sc=bpy.context.scene
# --- last shot: bank shows its BACK, cable peels out of its groove and goes up into the phone ---
pb=bpy.data.objects['PowerBank']
for fc in pb.animation_data.action.fcurves:
    if fc.data_path=='rotation_quaternion':
        for k in fc.keyframe_points:
            if round(k.co[0]) in (566,700):
                k.co[1]=(0,0,0,1)[fc.array_index]; k.handle_left[1]=k.co[1]; k.handle_right[1]=k.co[1]
c=bpy.data.objects['PB_CableAnim']; act=c.data.animation_data.action
rest=[(0.0165,0.005,-0.069),(0.0165,0.005,-0.06),(0.0165,0.005,-0.05),(0.0165,0.005,-0.04),(0.0165,0.005,-0.03),(0.0165,0.0045,-0.0185)]
keys={580:rest,
 # like the photo: cable stays in its groove at the bottom, the tip lifts straight up/out into the phone sitting right above it
 600:[(0.0165,0.005,-0.069),(0.0165,0.005,-0.055),(0.0165,0.008,-0.042),(0.0167,0.014,-0.031),(0.0170,0.019,-0.020),(0.0172,0.021,-0.007)],
 620:[(0.0165,0.005,-0.069),(0.0165,0.006,-0.053),(0.017,0.012,-0.039),(0.0185,0.021,-0.027),(0.0195,0.027,-0.015),(0.020,0.029,-0.004)],
 636:[(0.0165,0.005,-0.069),(0.0165,0.006,-0.052),(0.017,0.012,-0.038),(0.019,0.022,-0.026),(0.020,0.028,-0.014),(0.020,0.030,-0.004)],
 640:[(0.0165,0.005,-0.069),(0.0165,0.006,-0.052),(0.017,0.012,-0.038),(0.019,0.022,-0.026),(0.020,0.028,-0.012),(0.020,0.030,0.000)]}
# MIRROR_RIGHT: like the photo, pull the cable in the right-hand groove (as seen from the camera); left groove keeps its cable
keys={f:[(-p[0],p[1],p[2]) for p in pts] for f,pts in keys.items()}
for i,hid in ((0,False),(2,True)):
    for n in ('PB_Cable_%d','PB_Boot_%d','PB_Tip_%d'):
        o=bpy.data.objects[n%i]; o.hide_render=hid; o.hide_viewport=hid
for fc in list(act.fcurves):
    if fc.data_path.startswith('splines[0].points'): act.fcurves.remove(fc)
sp=c.data.splines[0]
for f,pts in sorted(keys.items()):
    for i,p in enumerate(pts):
        sp.points[i].co=(p[0],p[1],p[2],1.0); sp.points[i].keyframe_insert('co',frame=f)
r=bpy.data.objects['PB_PlugRig']; ra=r.animation_data.action
for fc in list(ra.fcurves): ra.fcurves.remove(fc)
for f,pts in sorted(keys.items()):
    r.location=pts[5]; r.keyframe_insert('location',frame=f)
    r.rotation_euler=(0,0,0); r.keyframe_insert('rotation_euler',frame=f)
# phone: port lines up with the cable end (bank local (-0.062,0.012,-0.020)), pushed up from below
L=mathutils.Vector((-0.03,-0.538,0.752)); port=L+mathutils.Vector((0.020,-0.030,0.000))
rig=port-mathutils.Vector((0,-0.002,-0.0895))
pr=bpy.data.objects['PhoneRig']
for fc in pr.animation_data.action.fcurves:
    if fc.data_path=='location':
        for k in fc.keyframe_points:
            fr=round(k.co[0])
            if fr in (576,700): v=rig[fc.array_index]
            elif fr==538: v=(rig.x,rig.y,rig.z+0.40)[fc.array_index]
            else: continue
            d=v-k.co[1]; k.co[1]=v; k.handle_left[1]+=d; k.handle_right[1]+=d
cam=bpy.data.objects['Cam_Film']; sc.camera=cam
cd=cam.data; cd.sensor_fit='HORIZONTAL'; cd.sensor_width=14.0
if cd.animation_data and cd.animation_data.action:
    for fc in list(cd.animation_data.action.fcurves):
        if fc.data_path.startswith('dof') or fc.data_path=='shift_y': cd.animation_data.action.fcurves.remove(fc)
cd.dof.use_dof=True; cd.dof.focus_object=bpy.data.objects['PowerBank']
for f,fs,sy in ((1,128,0.0),(560,128,0.0),(600,2.0,0.16),(700,2.0,0.16)):
    cd.dof.aperture_fstop=fs; cd.dof.keyframe_insert('aperture_fstop',frame=f)
    cd.shift_y=sy; cd.keyframe_insert('shift_y',frame=f)
nt=bpy.data.materials['Phone_Screen'].node_tree
rot=nt.nodes['Mapping'].inputs['Rotation']
for f,z in ((1,2.30),(560,2.45),(600,2.55),(650,2.85),(700,3.05)):
    rot.default_value[2]=z; rot.keyframe_insert('default_value',index=2,frame=f)
fcg=[x for x in nt.animation_data.action.fcurves if 'GlareShift' in x.data_path][0]; fcg.keyframe_points.clear()
g=nt.nodes['GlareShift'].outputs[0]
for f,v in ((1,-0.06),(560,0.0),(610,0.08),(660,0.20),(700,0.28)):
    g.default_value=v; g.keyframe_insert('default_value',frame=f)
sc.render.resolution_x=1080; sc.render.resolution_y=2340; sc.render.resolution_percentage=100
sc.render.image_settings.file_format='PNG'; sc.render.image_settings.color_mode='RGB'; sc.render.image_settings.compression=15
sc.render.use_motion_blur=False; sc.eevee.taa_render_samples=48

for f,sx in ((1,0.0),(560,0.0),(600,0.07),(700,0.07)):
    cd.shift_x=sx; cd.keyframe_insert('shift_x',frame=f)
for fc in cd.animation_data.action.fcurves:
    if fc.data_path=='lens':
        for k in fc.keyframe_points:
            if k.co[0]>=590: k.co[1]*=0.78; k.handle_left[1]*=0.78; k.handle_right[1]*=0.78

# CAMBG: camera rays outside the kiosk see a soft light backdrop instead of black (lighting unchanged)
w=bpy.context.scene.world; w.use_nodes=True; nt=w.node_tree
out=[n for n in nt.nodes if n.type=='OUTPUT_WORLD'][0]
src=out.inputs['Surface'].links[0].from_socket if out.inputs['Surface'].links else None
lp=nt.nodes.new('ShaderNodeLightPath'); bg=nt.nodes.new('ShaderNodeBackground'); bg.inputs[0].default_value=(0.80,0.81,0.82,1); bg.inputs[1].default_value=1.0
mx=nt.nodes.new('ShaderNodeMixShader')
if src: nt.links.new(src,mx.inputs[1])
nt.links.new(bg.outputs[0],mx.inputs[2]); nt.links.new(lp.outputs['Is Camera Ray'],mx.inputs[0]); nt.links.new(mx.outputs[0],out.inputs['Surface'])

# ---- CABLES_V2: real chargeFUZE cable construction (flat ribbon, wide molded boot, USB-C / Lightning / Micro-USB tips) ----
import bmesh, math
from mathutils import Vector
PBo=bpy.data.objects['PowerBank']
mCab=bpy.data.materials['PB_Cable']; mMet=bpy.data.materials['PB_Metal']
RW,RT,RY=0.0090,0.0014,0.0064        # ribbon width / thickness / depth in groove
def _mesh(name,bm,mat,parent=PBo,loc=(0,0,0)):
    o=bpy.data.objects.get(name)
    me=bpy.data.meshes.new(name+'_m'); bm.to_mesh(me); bm.free()
    if o is None:
        o=bpy.data.objects.new(name,me); PBo.users_collection[0].objects.link(o)
    else:
        o.data=me
    o.modifiers.clear()
    o.constraints.clear(); o.delta_location=(0,0,0); o.delta_rotation_euler=(0,0,0); o.delta_scale=(1,1,1)
    if o.animation_data: o.animation_data_clear()
    o.parent=parent; o.matrix_parent_inverse.identity(); o.location=loc; o.rotation_euler=(0,0,0); o.scale=(1,1,1)
    o.data.materials.clear(); o.data.materials.append(mat)
    for p in o.data.polygons: p.use_smooth=False
    bv=o.modifiers.new('bv','BEVEL'); bv.width=0.0003; bv.segments=2; bv.limit_method='ANGLE'
    return o
def loft(rings):
    bm=bmesh.new(); prev=None; first=None
    for r in rings:
        vs=[bm.verts.new(v) for v in r]
        if prev:
            n=len(vs)
            for i in range(n): bm.faces.new((prev[i],prev[(i+1)%n],vs[(i+1)%n],vs[i]))
        else: first=vs
        prev=vs
    bm.faces.new(list(reversed(first))); bm.faces.new(prev)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces); return bm
def rect(x,y,z,w,t,top=0.0):
    # rectangle in the XY plane at height z; optional chamfered corners
    c=min(w,t)*(0.35 if top else 0.12)
    if c: return [(x-w/2+c,y-t/2,z),(x+w/2-c,y-t/2,z),(x+w/2,y-t/2+c,z),(x+w/2,y+t/2-c,z),(x+w/2-c,y+t/2,z),(x-w/2+c,y+t/2,z),(x-w/2,y+t/2-c,z),(x-w/2,y-t/2+c,z)]
    return [(x-w/2,y-t/2,z),(x+w/2,y-t/2,z),(x+w/2,y+t/2,z),(x-w/2,y+t/2,z)]
def sweep(x,path,w,t):
    # flat ribbon along a path in the YZ plane (width along X)
    rings=[]
    for i,p in enumerate(path):
        a=Vector(path[max(i-1,0)]); b=Vector(path[min(i+1,len(path)-1)]); T=(b-a).normalized(); N=Vector((0,-T.y,T.x))
        P=Vector((x,p[0],p[1]))
        rings.append([tuple(P+Vector((-w/2,0,0))-N*t/2),tuple(P+Vector((w/2,0,0))-N*t/2),tuple(P+Vector((w/2,0,0))+N*t/2),tuple(P+Vector((-w/2,0,0))+N*t/2)])
    return loft(rings)
# bottom wrap: up the groove, round the bottom edge, a little way up the front
def wrap_path(ztop):
    pts=[(RY,ztop),(RY,-0.066)]
    for k in range(9):
        a=math.pi*k/8; pts.append((RY*math.cos(a), -0.0700-0.0012*math.sin(a)))
    pts+= [(-RY,-0.066),(-RY,-0.064)]
    return pts
def boot(x,z0):
    # molded strain-relief: tapers out from the ribbon to a wide flat block (like the real cable)
    return loft([rect(x,RY+0.0002,z0,RW,RT),rect(x,RY+0.0003,z0+0.0045,0.0104,0.0026,1),rect(x,RY+0.0003,z0+0.0135,0.0104,0.0026,1),rect(x,RY+0.0003,z0+0.0150,0.0094,0.0022,1)])
def tip(kind,x,z0):
    if kind=='usbc':  return loft([rect(x,RY+0.0004,z0,0.0084,0.0026,1),rect(x,RY+0.0004,z0+0.0066,0.0084,0.0026,1)])
    if kind=='light': return loft([rect(x,RY+0.0004,z0,0.0078,0.0015),rect(x,RY+0.0004,z0+0.0064,0.0078,0.0015),rect(x,RY+0.0004,z0+0.0075,0.0060,0.0013)])
    # micro-USB: trapezoid
    return loft([[(x-0.0034,RY+0.0004-0.0009,z0),(x+0.0034,RY+0.0004-0.0009,z0),(x+0.0027,RY+0.0004+0.0009,z0),(x-0.0027,RY+0.0004+0.0009,z0)],
                 [(x-0.0034,RY+0.0004-0.0009,z0+0.006),(x+0.0034,RY+0.0004-0.0009,z0+0.006),(x+0.0027,RY+0.0004+0.0009,z0+0.006),(x-0.0027,RY+0.0004+0.0009,z0+0.006)]])
# groove order seen from the back (left→right on screen): Micro-USB, Lightning, USB-C (USB-C is the one pulled into the iPhone)
KIND={0:'micro',1:'light',2:'usbc'}; GX={0:0.0128,1:0.0,2:-0.0128}   # BACK_V4: cables sit close together like the real bank
ZB=-0.0210   # boot starts here; tip ends at ZB+0.015+tip length ≈ -0.002
for i in (0,1,2):
    _mesh('PB_Cable_%d'%i, sweep(GX[i],wrap_path(ZB+0.0005),RW,RT), mCab)
    _mesh('PB_Boot_%d'%i, boot(GX[i],ZB), mCab)
    _mesh('PB_Tip_%d'%i, tip(KIND[i],GX[i],ZB+0.0150), mMet)
# the pulled cable (groove 2): its bottom wrap stays put, the rest is the animated ribbon
_mesh('PB_Wrap_2', sweep(GX[2],wrap_path(-0.0688)[1:],RW,RT), mCab)
for n in ('PB_Cable_2','PB_Boot_2','PB_Tip_2'):
    o=bpy.data.objects[n]; o.hide_render=True; o.hide_viewport=True
for n in ('PB_Cable_0','PB_Boot_0','PB_Tip_0','PB_Wrap_2'):
    o=bpy.data.objects[n]; o.hide_render=False; o.hide_viewport=False
# animated ribbon profile = same flat ribbon
pc=bpy.data.curves.get('CblProfile2') or bpy.data.curves.new('CblProfile2','CURVE')
pc.splines.clear(); sp2=pc.splines.new('POLY'); sp2.points.add(3)
for k,(a,b) in enumerate(((-RW/2,-RT/2),(RW/2,-RT/2),(RW/2,RT/2),(-RW/2,RT/2))): sp2.points[k].co=(a,b,0,1)
sp2.use_cyclic_u=True
po=bpy.data.objects.get('CblProfile2') or bpy.data.objects.new('CblProfile2',pc)
if not po.users_collection: PBo.users_collection[0].objects.link(po)
po.hide_render=True; po.hide_viewport=True
ca=bpy.data.objects['PB_CableAnim']; ca.data.bevel_mode='OBJECT'; ca.data.bevel_object=po; ca.data.use_fill_caps=True
# plug on the rig: rig origin = ribbon end (z rest -0.0185) → boot from -0.0055, tip above it
rgo=bpy.data.objects['PB_PlugRig']
_mesh('PB_Boot_Anim', boot(0,-0.0055), mCab, parent=rgo, loc=(0,-(RY+0.0004),0))
_mesh('PB_Tip_Anim', tip('usbc',0,-0.0055+0.0150), mMet, parent=rgo, loc=(0,-(RY+0.0004),0))
ta=bpy.data.objects['PB_Tip_Anim']
if ta.animation_data: ta.animation_data_clear()
ta.scale=(1,1,1); ta.location=(0,-(RY+0.0004),0)
# shift the ribbon anchor/tip y onto the new ribbon depth
for f,pts in keys.items(): pass

# ---- BANK_PROPORTIONS: real bank is ~2:1 tall and much thicker (~16 mm). Ease into it while it turns out of the slot.
if pb.animation_data and pb.animation_data.action:
    for fc in list(pb.animation_data.action.fcurves):
        if fc.data_path=='scale': pb.animation_data.action.fcurves.remove(fc)
for f,sv in ((500,(1.0,1.0,1.0)),(545,(0.92,1.30,1.13)),(700,(0.92,1.30,1.13))):
    pb.scale=sv; pb.keyframe_insert('scale',frame=f)

# ---- TILT_V3: bank tilted like the photo (top leans left), phone upright directly above the pulled cable,
# plug goes INTO the phone's bottom edge, whole group centred in frame ----
import math
from mathutils import Vector, Quaternion, Matrix
TH=math.radians(10)
sn,cs=math.sin(TH),math.cos(TH)
LEAN=0.0
QBq=Quaternion((0,0,0,1))@Quaternion((0,1,0),TH)@Quaternion((1,0,0),LEAN)
QB=tuple(QBq)
for fc in pb.animation_data.action.fcurves:
    if fc.data_path=='rotation_quaternion':
        for k in fc.keyframe_points:
            if round(k.co[0]) in (566,700):
                k.co[1]=QB[fc.array_index]; k.handle_left[1]=k.co[1]; k.handle_right[1]=k.co[1]
u=(QBq.to_matrix().transposed()@Vector((0,0,1))).normalized()   # world-up expressed in bank space
g=-0.0128
# like the real photo: only the very bottom stays in the groove; the whole free length lifts off and runs
# straight up (world vertical) in one gentle bow into the device sitting over the bank's right edge. No fold.
A0=Vector((g,RY,-0.062))
Pend=A0+u*0.058+Vector((0,0.012,0))
_p1=Vector((g,RY+0.0005,-0.061)); _c1=_p1+Vector((0,0.004,0.016)); _c2=Pend-u*0.016
def _bz(t): return (1-t)**3*_p1+3*(1-t)**2*t*_c1+3*(1-t)*t*t*_c2+t**3*Pend
F=[Vector((g,RY,-0.069)),_p1,_bz(0.3),_bz(0.6),_bz(0.85),Pend]   # one smooth bend, no S
R0=[Vector((g,RY,-0.069)),Vector((g,RY,-0.058)),Vector((g,RY,-0.047)),Vector((g,RY,-0.037)),Vector((g,RY,-0.026)),Vector((g,RY,-0.0155))]
def kk(lift):
    # the tip leads, the lower points follow later, so it peels out of the groove from the top down
    out=[]
    for i,(a0,b0) in enumerate(zip(R0,F)):
        w=max(0.0,min(1.0,(lift-(5-i)*0.05)/(1-(5-i)*0.05))) if i<5 else lift
        w=w*w*(3-2*w)
        out.append(tuple(a0.lerp(b0,w)))
    return out
keys={580:kk(0),600:kk(0.35),620:kk(0.8),636:kk(0.97),640:kk(1.0)}
ROT={580:0,600:-TH*0.35,620:-TH*0.8,636:-TH*0.97,640:-TH}
for fc in list(act.fcurves):
    if fc.data_path.startswith('splines[0].points'): act.fcurves.remove(fc)
for f,pts in sorted(keys.items()):
    for i,pt in enumerate(pts):
        sp.points[i].co=(pt[0],pt[1],pt[2],1.0); sp.points[i].keyframe_insert('co',frame=f)
for fc in list(ra.fcurves): ra.fcurves.remove(fc)
for f,pts in sorted(keys.items()):
    r.location=pts[5]; r.keyframe_insert('location',frame=f)
    r.rotation_euler=(0,ROT[f],0); r.keyframe_insert('rotation_euler',frame=f)
vl=bpy.context.view_layer
def phone_bottom():
    dg=bpy.context.evaluated_depsgraph_get(); pts=[]
    for o in pr.children_recursive:
        if o.type=='MESH' and not o.hide_render:
            oe=o.evaluated_get(dg); pts+=[oe.matrix_world@Vector(c) for c in oe.bound_box]
    zs=min(p.z for p in pts); xs=[p.x for p in pts]; ys=[p.y for p in pts]
    return Vector(((min(xs)+max(xs))/2,(min(ys)+max(ys))/2,zs)), pts
for it in range(2):
    sc.frame_set(700); vl.update()
    target=pb.matrix_world@(Pend+u*0.0095)   # top of the boot = phone's bottom edge
    target=target+(cam.matrix_world.to_3x3()@Vector((0,0,1))).normalized()*0.0055   # plug goes into the phone body, not in front of the glass
    B,_=phone_bottom(); d=target-B
    M=pr.parent.matrix_world.to_3x3().inverted() if pr.parent else Matrix.Identity(3)
    dl=M@d
    for fc in pr.animation_data.action.fcurves:
        if fc.data_path=='location':
            for k in fc.keyframe_points:
                if round(k.co[0]) in (538,576,700):
                    k.co[1]+=dl[fc.array_index]; k.handle_left[1]+=dl[fc.array_index]; k.handle_right[1]+=dl[fc.array_index]
# centre the bank+phone group in frame
from bpy_extras.object_utils import world_to_camera_view
for it in range(3):
    sc.frame_set(700); vl.update()
    _,pts=phone_bottom()
    dg=bpy.context.evaluated_depsgraph_get(); bo=bpy.data.objects['PB_Body'].evaluated_get(dg)
    pts+=[bo.matrix_world@Vector(c) for c in bo.bound_box]
    P=[world_to_camera_view(sc,cam,q) for q in pts]
    cx=(min(q.x for q in P)+max(q.x for q in P))/2; cy=(min(q.y for q in P)+max(q.y for q in P))/2
    for fc in cd.animation_data.action.fcurves:
        if fc.data_path in ('shift_x','shift_y'):
            for k in fc.keyframe_points:
                if round(k.co[0]) in (600,700):
                    dv=(cx-0.5) if fc.data_path=='shift_x' else (cy-0.5)*sc.render.resolution_y/sc.render.resolution_x
                    k.co[1]+=dv; k.handle_left[1]+=dv; k.handle_right[1]+=dv
open('/Users/vunguyen/Desktop/iphone-18-pro-max-high-quality-3d-model/_vert/center.txt','w').write('%f %f'%(cx,cy))

# ---- SHALLOW_BACK (like the real banks on the table): flat back, wide ribbons almost touching,
# a small navy slot under the port icons that the plugs tuck into ----
pk=bpy.data.objects['PB_Cut_Pocket']; pk.scale=(0.050/0.064,0.0070/0.008,0.017/0.026); pk.location=(0.0,0.0063,-0.0085)
for i in (0,1,2):
    gb=bpy.data.objects['PB_Cut_GrooveBack_%d'%i]; gb.scale=(0.0100/0.0124,0.0010/0.0028,1.0); gb.location.y=0.0063; gb.location.x=GX[i]
    for nm in ('PB_Cut_GrooveBottom_%d','PB_Cut_GrooveFront_%d'):
        o=bpy.data.objects[nm%i]; o.scale.x=0.0100/0.0124; o.location.x=GX[i]
bs=bpy.data.materials['PB_Recess'].node_tree.nodes['Principled BSDF']; bs.inputs['Base Color'].default_value=(0.012,0.022,0.060,1); bs.inputs['Roughness'].default_value=0.55

# ---- BACK_LAYOUT (from the video): LEDs lower-left above "Return this way", regulatory block on the right
for i in range(4):
    o=bpy.data.objects.get('PB_LED_%d'%i)
    if o: o.location.z=-0.0105
reg=bpy.data.objects.get('PB_B_Reg')
if reg is None:
    cu=bpy.data.curves.new('PB_B_Reg','FONT')
    cu.body="Fuze Technology, Inc.\nModel: CFN-1-21\nBattery 3.7V 5000mAh\nInput 5V 1.5A\nOutput 5V 2.0A (Max)\nCE FC IC\nMade in China"
    cu.size=0.0026; cu.space_line=1.15; cu.align_x='LEFT'
    reg=bpy.data.objects.new('PB_B_Reg',cu); PBo.users_collection[0].objects.link(reg)
    reg.data.materials.append(bpy.data.materials['PB_PrintWhite'])
reg.parent=PBo; reg.matrix_parent_inverse.identity()
reg.data.size=0.0017; reg.location=(-0.0205,0.0065,-0.030); reg.rotation_euler=(math.pi/2,0,math.pi)

# ---- SIDE_DETAILS (from the photos): blue Power On button + USB-C on the long sides, pogo pins on the bottom end
def _bx(name,size,loc,mat):
    bm=bmesh.new(); bmesh.ops.create_cube(bm,size=1.0)
    for v in bm.verts: v.co=Vector((v.co.x*size[0],v.co.y*size[1],v.co.z*size[2]))
    o=_mesh(name,bm,mat); o.location=loc; return o
_bx('PB_PowerBtn',(0.0016,0.0055,0.0105),(0.0402,0.0,-0.050),bpy.data.materials['PB_PrintBlue'])
_bx('PB_USBC',(0.0016,0.0032,0.0090),(-0.0402,0.0,-0.046),bpy.data.materials['PB_Recess'])
_bx('PB_Jack',(0.0016,0.0035,0.0035),(-0.0402,0.0,-0.058),bpy.data.materials['PB_Recess'])
for i,xp in enumerate((0.030,0.026,-0.026,-0.030)):
    _bx('PB_Pogo_%d'%i,(0.0022,0.0022,0.0012),(xp,0.0,-0.0703),bpy.data.materials['PB_Metal'])

# ---- BACK_V4 (photos): flat back with no big shading facets, small printed port icons right above each plug
_old={0:0.0165,1:0.0,2:-0.0165}
for i in (0,1,2):
    for nm in ('PB_Port_%d','PB_PortIn_%d'):
        o=bpy.data.objects.get(nm%i)
        if o: o.scale=(0.72,1,0.72); o.location.x=GX[i]-0.72*_old[i]; o.location.z=0.0035+0.0050   # icons sit above the slot
bd=bpy.data.objects['PB_Body']; me=bd.data
try:
    me.use_auto_smooth=True; me.auto_smooth_angle=math.radians(35)
except Exception: pass
for p in me.polygons: p.use_smooth=True
if not any(m.type=='WEIGHTED_NORMAL' for m in bd.modifiers):
    wn=bd.modifiers.new('wn','WEIGHTED_NORMAL'); wn.keep_sharp=True; wn.mode='FACE_AREA'

# ---- PLUGS_HIDDEN (IMG_0124): the plugs live under the cover; only the flat ribbons show, diving into a slot
# right under the printed port icons. The pulled cable's plug slides out of that slot.
ZS=0.0042   # slot line
for i in (0,1,2):
    path=[(RY-0.0035,ZS+0.0040),(RY-0.0012,ZS+0.0012)]+wrap_path(ZS-0.0010)
    _mesh('PB_Cable_%d'%i, sweep(GX[i],path,RW,RT), mCab)
    for n in ('PB_Boot_%d','PB_Tip_%d'):
        o=bpy.data.objects[n%i]; o.hide_render=True; o.hide_viewport=True
    _bx('PB_Slot_%d'%i,(RW+0.0016,0.0010,0.0016),(GX[i],RY+0.0004,ZS+0.0004),bpy.data.materials['PB_Recess'])
bpy.data.objects['PB_Cable_2'].hide_render=True; bpy.data.objects['PB_Cable_2'].hide_viewport=True
# pulled cable: at rest its plug is tucked inside the slot (hidden), then slides out
fr=[k for k in sorted(keys)]
P0=list(keys[580]); top=Vector(P0[5]); P0[5]=(top.x,RY-0.0040,ZS+0.0060); P0[4]=(top.x,RY-0.0005,ZS-0.0030)
keys[580]=P0
for fc in list(act.fcurves):
    if fc.data_path.startswith('splines[0].points'): act.fcurves.remove(fc)
for f,pts in sorted(keys.items()):
    for i,pt in enumerate(pts):
        sp.points[i].co=(pt[0],pt[1],pt[2],1.0); sp.points[i].keyframe_insert('co',frame=f)
r.location=P0[5]; r.keyframe_insert('location',frame=580)
# before 580 the visible pulled cable must also look tucked: hold the 580 pose from the start
for f in (500,545):
    for i,pt in enumerate(P0):
        sp.points[i].co=(pt[0],pt[1],pt[2],1.0); sp.points[i].keyframe_insert('co',frame=f)
    r.location=P0[5]; r.keyframe_insert('location',frame=f)
sc.eevee.taa_render_samples=160   # calmer bokeh: no shimmer in the blurred kiosk behind
bpy.data.objects['PB_B_Secure'].location.z=0.0120
# ---- SMOOTH_CAM: one continuous ease instead of three overlapping ones (the background was surging = "shaky")
sc.eevee.taa_render_samples=96
for fc in cd.animation_data.action.fcurves:
    if fc.data_path in ('shift_x','shift_y','dof.aperture_fstop'):
        for k in fc.keyframe_points:
            if round(k.co[0])==560: k.co[0]=505
            elif round(k.co[0])==600: k.co[0]=572
for fc in cam.animation_data.action.fcurves:
    if fc.data_path=='location':
        ks=[k for k in fc.keyframe_points if round(k.co[0])==540]
        for k in ks: fc.keyframe_points.remove(k)
    for k in fc.keyframe_points: k.handle_left_type='AUTO_CLAMPED'; k.handle_right_type='AUTO_CLAMPED'
    fc.update()
for fc in cd.animation_data.action.fcurves:
    for k in fc.keyframe_points: k.handle_left_type='AUTO_CLAMPED'; k.handle_right_type='AUTO_CLAMPED'
    fc.update()

# ---- RIBBON_FIX: the lifted cable is a FLAT ribbon of constant width (no twist). Rebuild it as a mesh every frame:
# smooth path through the animated control points, width always along the bank's X axis.
import bpy, bmesh
from mathutils import Vector
_ca=bpy.data.objects['PB_CableAnim']; _ca.hide_render=True; _ca.hide_viewport=True
_act=_ca.data.animation_data.action
_rib=bpy.data.objects.get('PB_RibbonAnim')
if _rib is None:
    _rib=bpy.data.objects.new('PB_RibbonAnim',bpy.data.meshes.new('PB_RibbonAnim_m')); PBo.users_collection[0].objects.link(_rib)
_rib.parent=PBo; _rib.matrix_parent_inverse.identity(); _rib.location=(0,0,0); _rib.rotation_euler=(0,0,0); _rib.scale=(1,1,1)
def _cp(f):
    P=[]
    for i in range(6):
        P.append(Vector([_act.fcurves.find('splines[0].points[%d].co'%i,index=k).evaluate(f) for k in range(3)]))
    return P
def _bspline(P,n=48):
    # clamped cubic B-spline (passes through both ends, smooth in between) – same feel as the NURBS curve
    k=4; m=len(P); kn=[0]*k+list(range(1,m-k+1))+[m-k+1]*k; kn=[x/(m-k+1) for x in kn]
    def N(i,p,t):
        if p==0: return 1.0 if (kn[i]<=t<kn[i+1] or (t==1.0 and kn[i+1]==1.0 and kn[i]<1.0)) else 0.0
        a=0 if kn[i+p]==kn[i] else (t-kn[i])/(kn[i+p]-kn[i])*N(i,p-1,t)
        b=0 if kn[i+p+1]==kn[i+1] else (kn[i+p+1]-t)/(kn[i+p+1]-kn[i+1])*N(i+1,p-1,t)
        return a+b
    out=[]
    for j in range(n+1):
        t=min(j/n,1.0); v=Vector((0,0,0))
        for i in range(m): v+=N(i,k-1,t)*P[i]
        out.append(v)
    return out
def _ribbon(f):
    pts=_bspline(_cp(f)); X=Vector((1,0,0)); bm=bmesh.new(); rings=[]
    for i,p in enumerate(pts):
        T=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized()
        W=(X-X.dot(T)*T).normalized(); Nn=T.cross(W).normalized()
        rings.append([bm.verts.new(p+W*sx*RW/2+Nn*sy*RT/2) for sx,sy in ((-1,-1),(1,-1),(1,1),(-1,1))])
    for a,b in zip(rings,rings[1:]):
        for q in range(4): bm.faces.new((a[q],a[(q+1)%4],b[(q+1)%4],b[q]))
    bm.faces.new(list(reversed(rings[0]))); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    bm.to_mesh(_rib.data); bm.free()
    if not _rib.data.materials: _rib.data.materials.append(mCab)
    for pg in _rib.data.polygons: pg.use_smooth=True
def _ribbon_handler(scene,*a): _ribbon(scene.frame_current)
for h in list(bpy.app.handlers.frame_change_pre):
    if getattr(h,'__name__','')=='_ribbon_handler': bpy.app.handlers.frame_change_pre.remove(h)
bpy.app.handlers.frame_change_pre.append(_ribbon_handler)
_ribbon(sc.frame_current)

# ---- RECESS_FIX (IMG_0124): the finger recess is a black, rounded hollow, not a navy window
_bs=bpy.data.materials['PB_Recess'].node_tree.nodes['Principled BSDF']; _bs.inputs['Base Color'].default_value=(0.006,0.006,0.008,1); _bs.inputs['Roughness'].default_value=0.6
_pk=bpy.data.objects['PB_Cut_Pocket']
if not any(m.type=='BEVEL' for m in _pk.modifiers):
    _bv=_pk.modifiers.new('round','BEVEL'); _bv.width=0.0045; _bv.segments=8; _bv.limit_method='NONE'; _bv.affect='EDGES'

# ---- REAL_DETAILS (IMG_0110-0124): parts the photos show that were missing or wrong
import math, bmesh
from mathutils import Vector, Matrix
_bd=bpy.data.objects['PB_Body']; _vs=[v.co for v in _bd.data.vertices]
HX=max(v.x for v in _vs); HZ=max(v.z for v in _vs); LZ=min(v.z for v in _vs); BY=max(v.y for v in _vs)
open('/Users/vunguyen/Desktop/iphone-18-pro-max-high-quality-3d-model/_vert/inspect12.txt','w').write('HX %f HZ %f LZ %f BY %f'%(HX,HZ,LZ,BY))
def _emis(name,col,strength):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name); m.use_nodes=True; nt=m.node_tree; nt.nodes.clear()
    o=nt.nodes.new('ShaderNodeOutputMaterial'); e=nt.nodes.new('ShaderNodeEmission'); e.inputs[0].default_value=col; e.inputs[1].default_value=strength
    nt.links.new(e.outputs[0],o.inputs[0]); return m
mLed=_emis('PB_LedOn',(0.05,0.35,1,1),18.0)
def _cyl(name,r,d,loc,axis,mat,seg=40):
    bm=bmesh.new(); bmesh.ops.create_cone(bm,cap_ends=True,segments=seg,radius1=r,radius2=r,depth=d)
    if axis=='X': bmesh.ops.rotate(bm,verts=bm.verts,cent=(0,0,0),matrix=Matrix.Rotation(math.pi/2,3,'Y'))
    if axis=='Y': bmesh.ops.rotate(bm,verts=bm.verts,cent=(0,0,0),matrix=Matrix.Rotation(math.pi/2,3,'X'))
    o=_mesh(name,bm,mat); o.location=loc; return o
# side A (power side): round blue button + small round hole near the bottom end, "Power On" printed along the side
for n in ('PB_PowerBtn',):
    o=bpy.data.objects.get(n)
    if o: o.hide_render=True; o.hide_viewport=True
_cyl('PB_PowerBtnR',0.0029,0.0014,(HX+0.0003,0.0,LZ+0.019),'X',bpy.data.materials['PB_PrintBlue'])
_cyl('PB_PowerHole',0.0017,0.0010,(HX+0.0001,0.0,LZ+0.0095),'X',bpy.data.materials['PB_Recess'])
cu=bpy.data.curves.get('PB_PowerTxt') or bpy.data.curves.new('PB_PowerTxt','FONT'); cu.body='Power On'; cu.size=0.0034; cu.align_x='LEFT'; cu.align_y='CENTER'
pt=bpy.data.objects.get('PB_PowerTxt') or bpy.data.objects.new('PB_PowerTxt',cu)
if not pt.users_collection: PBo.users_collection[0].objects.link(pt)
pt.data.materials.clear(); pt.data.materials.append(bpy.data.materials['PB_PrintWhite'])
pt.parent=PBo; pt.matrix_parent_inverse.identity()
pt.matrix_basis=Matrix.Translation((HX+0.0002,0.0,LZ+0.030))@Matrix(((0,0,1,0),(0,-1,0,0),(1,0,0,0),(0,0,0,1)))
# tiny arrow before the text pointing at the button
bm=bmesh.new(); v=[bm.verts.new(p) for p in ((0,0.0016,0),(0,-0.0016,0),(0,0,-0.0026))]; bm.faces.new(v)
ar=_mesh('PB_PowerArrow',bm,bpy.data.materials['PB_PrintWhite']); ar.location=(HX+0.0002,0,LZ+0.0272); ar.modifiers.clear()
# side B: round hole + USB-C near the bottom end
o=bpy.data.objects.get('PB_Jack')
if o: o.hide_render=True; o.hide_viewport=True
_cyl('PB_JackR',0.0017,0.0010,(-HX-0.0001,0.0,LZ+0.0095),'X',bpy.data.materials['PB_Recess'])
o=bpy.data.objects.get('PB_USBC')
if o: o.location=(-HX-0.0002,0.0,LZ+0.019)
# bottom end: 3 gold pogo pins each side of the cables
for i in range(4):
    o=bpy.data.objects.get('PB_Pogo_%d'%i)
    if o: o.hide_render=True; o.hide_viewport=True
k=0
for sx in (1,-1):
    for xp in (0.021,0.025,0.029):
        _cyl('PB_PogoR_%d'%k,0.0011,0.0010,(sx*xp,0.0,LZ-0.0002),'Z',bpy.data.materials['PB_Metal'],seg=24); k+=1
# top end: the glowing blue status light bar
bm=bmesh.new(); bmesh.ops.create_cube(bm,size=1.0)
for vv in bm.verts: vv.co=Vector((vv.co.x*0.011,vv.co.y*0.0022,vv.co.z*0.0008))
lb=_mesh('PB_TopLight',bm,mLed); lb.location=(0,0,HZ+0.0001); lb.modifiers.clear()
# back: 3 of 4 LEDs lit blue
for i in range(4):
    o=bpy.data.objects.get('PB_LED_%d'%i)
    if o: o.data.materials.clear(); o.data.materials.append(mLed if i>0 else bpy.data.materials['PB_Recess'])
# back: chunky white block arrow "Return this way" (not a thin glyph)
o=bpy.data.objects.get('PB_B_Arrow')
if o:
    ax,az=o.location.x,o.location.z; o.hide_render=True; o.hide_viewport=True
    P=[(-0.0021,0.004),(0.0021,0.004),(0.0021,-0.0005),(0.0046,-0.0005),(0,-0.0050),(-0.0046,-0.0005),(-0.0021,-0.0005)]
    bm=bmesh.new(); vs=[bm.verts.new((ax+px,BY+0.00005,az-0.001+pz)) for px,pz in P]; f=bm.faces.new(vs)
    if f.normal.y<0: f.normal_flip()
    ba=_mesh('PB_B_ArrowBlock',bm,bpy.data.materials['PB_PrintWhite']); ba.modifiers.clear()
# gold pogo pins like the photo
_g=bpy.data.materials.get('PB_Gold') or bpy.data.materials.new('PB_Gold'); _g.use_nodes=True
_p=_g.node_tree.nodes.get('Principled BSDF'); _p.inputs['Base Color'].default_value=(0.83,0.62,0.25,1); _p.inputs['Metallic'].default_value=1.0; _p.inputs['Roughness'].default_value=0.28
for i in range(6):
    o=bpy.data.objects.get('PB_PogoR_%d'%i)
    if o: o.data.materials.clear(); o.data.materials.append(_g)

# ---- PLUG_SLOT_V2 (IMG_0124 close-up): each cable = narrow flat ribbon that widens (concave shoulders) into a wide flat
# boot; the boot pushes into its own rectangular slot right under the port icon (metal plug hidden inside). A dark bay with
# rounded ends sits right under the boots. Boots almost touch.
RW=0.0058; BW=0.0095; BT=0.0024; PITCH=0.0110
GX={0:PITCH,1:0.0,2:-PITCH}; g=-PITCH
def boot2(x,z0):
    prof=[(0.0,RW,RT),(0.0012,RW+0.0006,RT*1.1),(0.0026,0.0080,BT*0.85),(0.0040,0.0091,BT),(0.0052,BW,BT),(0.0150,BW,BT)]
    return loft([rect(x,RY+0.0002+(t-RT)/2,z0+dz,w,t,1 if w>RW+0.001 else 0) for dz,w,t in prof])
ZB2=ZS-0.0150
for i in (0,1,2):
    _mesh('PB_Cable_%d'%i, sweep(GX[i],wrap_path(ZB2+0.0004),RW,RT), mCab)
    _mesh('PB_Boot_%d'%i, boot2(GX[i],ZB2), mCab)
    bo=bpy.data.objects['PB_Boot_%d'%i]; bo.hide_render=(i==2); bo.hide_viewport=(i==2)
    t=bpy.data.objects['PB_Tip_%d'%i]; t.hide_render=True; t.hide_viewport=True
    _bx('PB_Slot_%d'%i,(BW+0.0012,0.0010,0.0020),(GX[i],RY+0.0004,ZS+0.0010),bpy.data.materials['PB_Recess'])
for n in ('PB_Cable_2',):
    o=bpy.data.objects[n]; o.hide_render=True; o.hide_viewport=True
_mesh('PB_Wrap_2', sweep(GX[2],wrap_path(-0.0688)[1:],RW,RT), mCab)
for i in (0,1,2):
    gb=bpy.data.objects['PB_Cut_GrooveBack_%d'%i]; gb.scale.x=(RW+0.0007)/0.0124; gb.location.x=GX[i]
    for nm in ('PB_Cut_GrooveBottom_%d','PB_Cut_GrooveFront_%d'):
        o=bpy.data.objects[nm%i]; o.scale.x=(RW+0.0007)/0.0124; o.location.x=GX[i]
for i in (0,1,2):
    for nm in ('PB_Port_%d','PB_PortIn_%d'):
        o=bpy.data.objects.get(nm%i)
        if o: o.location.x=GX[i]-0.72*_old[i]
# dark finger bay right under the boots, rounded ends, wider than the three cables
pk=bpy.data.objects['PB_Cut_Pocket']; pk.scale=(0.046/0.064,0.0060/0.008,0.0140/0.026); pk.location=(0.0,0.0063,ZB2-0.0045)
# pulled cable: its boot is the animated one; at rest it sits in its slot exactly like the other two
rgo=bpy.data.objects['PB_PlugRig']
_mesh('PB_Boot_Anim', boot2(0,-0.0055), mCab, parent=rgo, loc=(0,-(RY+0.0004),0))
ta=bpy.data.objects['PB_Tip_Anim']
if ta.animation_data and ta.animation_data.action:
    for fc in list(ta.animation_data.action.fcurves):
        if fc.data_path=='scale': ta.animation_data.action.fcurves.remove(fc)
for f,sv in ((500,0.0001),(586,0.0001),(592,1.0),(636,1.0),(639,0.0001)):
    ta.scale=(sv,sv,sv); ta.keyframe_insert('scale',frame=f)
rest_end=Vector((g,RY,ZB2+0.0055)); rest=[Vector((g,RY,z)) for z in (-0.069,-0.058,-0.047,-0.037,rest_end.z-0.010)]+[rest_end]
# re-key the pulled cable with the new spacing/rest pose (same lift timing as before)
A0=Vector((g,RY,-0.062)); Pend=A0+u*0.058+Vector((0,0.012,0))
_p1=Vector((g,RY+0.0005,-0.061)); _c1=_p1+Vector((0,0.004,0.016)); _c2=Pend-u*0.016
def _bz2(t): return (1-t)**3*_p1+3*(1-t)**2*t*_c1+3*(1-t)*t*t*_c2+t**3*Pend
F=[Vector((g,RY,-0.069)),_p1,_bz2(0.3),_bz2(0.6),_bz2(0.85),Pend]
def kk2(lift):
    out=[]
    for i,(a0,b0) in enumerate(zip(rest,F)):
        w=max(0.0,min(1.0,(lift-(5-i)*0.05)/(1-(5-i)*0.05))) if i<5 else lift
        w=w*w*(3-2*w); out.append(tuple(a0.lerp(b0,w)))
    return out
keys2={500:kk2(0),545:kk2(0),580:kk2(0),600:kk2(0.35),620:kk2(0.8),636:kk2(0.97),640:kk2(1.0)}
for fc in list(act.fcurves):
    if fc.data_path.startswith('splines[0].points'): act.fcurves.remove(fc)
for f,pts in sorted(keys2.items()):
    for i,pt in enumerate(pts):
        sp.points[i].co=(pt[0],pt[1],pt[2],1.0); sp.points[i].keyframe_insert('co',frame=f)
for fc in list(ra.fcurves):
    if fc.data_path=='location': ra.fcurves.remove(fc)
for f,pts in sorted(keys2.items()):
    r.location=pts[5]; r.keyframe_insert('location',frame=f)
_ribbon(sc.frame_current)

# ---- NECK_V3 (close-up photo): ribbon -> boot is a long smooth bottle-neck curve (S-shaped fillet), not a short chamfer
def boot3(x,z0):
    LT=0.0080; rings=[]
    for k in range(15):
        s=k/14.0; w=RW+(BW-RW)*(s*s*s*(s*(s*6-15)+10)); t=RT+(BT-RT)*min(1.0,s*1.6)
        rings.append(rect(x,RY+0.0002+(t-RT)/2,z0+LT*s-0.0028,w,t,1 if w>RW+0.0015 else 0))
    rings.append(rect(x,RY+0.0002+(BT-RT)/2,z0+0.0150,BW,BT,1))
    return loft(rings)
for i in (0,1,2):
    _mesh('PB_Boot_%d'%i, boot3(GX[i],ZB2), mCab)
    bo=bpy.data.objects['PB_Boot_%d'%i]; bo.hide_render=(i==2); bo.hide_viewport=(i==2)
_mesh('PB_Boot_Anim', boot3(0,-0.0055), mCab, parent=rgo, loc=(0,-(RY+0.0004),0))
for n in ('PB_Boot_0','PB_Boot_1','PB_Boot_2','PB_Boot_Anim'):
    o=bpy.data.objects[n]
    for pg in o.data.polygons: pg.use_smooth=True
    try: o.data.use_auto_smooth=True; o.data.auto_smooth_angle=math.radians(50)
    except Exception: pass

# ---- TRAY_V2 (empty-tray photo + IMG_0124): the hollow under the boots is a rectangle with two round "ears"
# (semicircles) on the left and right, and a raised ledge runs across inside it, just below the boot necks.
_pz=ZB2-0.0045
pk=bpy.data.objects['PB_Cut_Pocket']; pk.scale=(0.034/0.064,0.0060/0.008,0.0140/0.026); pk.location=(0.0,0.0063,_pz)
for m in pk.modifiers:
    if m.type=='BEVEL': m.width=0.0025
def _ear(name,x):
    bm=bmesh.new(); bmesh.ops.create_cone(bm,cap_ends=True,segments=48,radius1=0.0068,radius2=0.0068,depth=0.0060)
    bmesh.ops.rotate(bm,verts=bm.verts,cent=(0,0,0),matrix=Matrix.Rotation(math.pi/2,3,'X'))
    me=bpy.data.meshes.new(name+'_m'); bm.to_mesh(me); bm.free()
    o=bpy.data.objects.get(name)
    if o is None: o=bpy.data.objects.new(name,me); PBo.users_collection[0].objects.link(o)
    else: o.data=me
    o.parent=PBo; o.matrix_parent_inverse.identity(); o.location=(x,0.0063,_pz); o.rotation_euler=(0,0,0); o.scale=(1,1,1)
    o.hide_render=True; o.hide_viewport=True; o.display_type='WIRE'
    if not any(md.type=='BOOLEAN' and md.object==o for md in _bd.modifiers):
        b=_bd.modifiers.new(name,'BOOLEAN'); b.operation='DIFFERENCE'; b.object=o; b.solver='EXACT'
    return o
_ear('PB_Cut_EarL',0.0170); _ear('PB_Cut_EarR',-0.0170)
_ld=bpy.data.materials.get('PB_Ledge') or bpy.data.materials.new('PB_Ledge'); _ld.use_nodes=True
_lp=_ld.node_tree.nodes.get('Principled BSDF'); _lp.inputs['Base Color'].default_value=(0.028,0.028,0.032,1); _lp.inputs['Roughness'].default_value=0.55
bm=bmesh.new(); bmesh.ops.create_cube(bm,size=1.0)
for vv in bm.verts: vv.co=Vector((vv.co.x*0.0440,vv.co.y*0.0030,vv.co.z*0.0034))
lg=_mesh('PB_TrayLedge',bm,_ld); lg.location=(0.0,BY-0.0030,_pz-0.0030)

# ---- TRAY_V3 (empty-tray photo): ONE recessed tray under the cables. On its floor: two raised ribs that make the three
# cable channels (from the bottom end up), a raised platform with a screw hole, and short fingers on the platform that
# form three slots for the boots right under the port icons. Round finger notches cut into both long sides of the tray
# beside the platform. (Replaces the earlier pocket / ears / ledge / groove cutters.)
for md in _bd.modifiers:
    if md.type=='BOOLEAN' and md.object and md.object.name.startswith(('PB_Cut_Pocket','PB_Cut_Ear','PB_Cut_GrooveBack')):
        md.show_render=False; md.show_viewport=False
o=bpy.data.objects.get('PB_TrayLedge')
if o: o.hide_render=True; o.hide_viewport=True
for i in range(3):
    o=bpy.data.objects.get('PB_Slot_%d'%i)
    if o: o.hide_render=True; o.hide_viewport=True
TW=0.0165; TD=0.0034; TOP=ZS+0.0002; BOT=-0.0705
def _cutter(name,bm,loc):
    me=bpy.data.meshes.new(name+'_m'); bm.to_mesh(me); bm.free()
    o=bpy.data.objects.get(name)
    if o is None: o=bpy.data.objects.new(name,me); PBo.users_collection[0].objects.link(o)
    else: o.data=me
    o.parent=PBo; o.matrix_parent_inverse.identity(); o.location=loc; o.rotation_euler=(0,0,0); o.scale=(1,1,1)
    o.hide_render=True; o.hide_viewport=True; o.display_type='WIRE'
    if not any(md.type=='BOOLEAN' and md.object==o for md in _bd.modifiers):
        b=_bd.modifiers.new(name,'BOOLEAN'); b.operation='DIFFERENCE'; b.object=o; b.solver='EXACT'
    return o
bm=bmesh.new(); bmesh.ops.create_cube(bm,size=1.0)
for vv in bm.verts: vv.co=Vector((vv.co.x*2*TW,vv.co.y*0.010,vv.co.z*(TOP-BOT+0.004)))
_cutter('PB_Cut_Tray',bm,(0.0,BY-TD+0.005,(TOP+BOT)/2-0.002))
ZP1=ZS-0.0100; ZP0=ZS-0.0230; ZE=(ZP0+ZP1)/2-0.001
for nm,sx in (('PB_Cut_NotchL',1),('PB_Cut_NotchR',-1)):
    bm=bmesh.new(); bmesh.ops.create_cone(bm,cap_ends=True,segments=48,radius1=0.0072,radius2=0.0072,depth=0.010)
    bmesh.ops.rotate(bm,verts=bm.verts,cent=(0,0,0),matrix=Matrix.Rotation(math.pi/2,3,'X'))
    _cutter(nm,bm,(sx*TW,BY-TD+0.005,ZE))
def _blk(name,x0,x1,z0,z1,ytop,mat):
    bm=bmesh.new(); bmesh.ops.create_cube(bm,size=1.0)
    for vv in bm.verts: vv.co=Vector((vv.co.x*(x1-x0),vv.co.y*(ytop-(BY-TD-0.0005)),vv.co.z*(z1-z0)))
    o=_mesh(name,bm,mat); o.location=((x0+x1)/2,(ytop+BY-TD-0.0005)/2,(z0+z1)/2)
    for m in o.modifiers:
        if m.type=='BEVEL': m.width=0.0004
    return o
mB=bpy.data.materials['PB_Body']
CH=RW+0.0008
for k,xc in enumerate((PITCH/2,-PITCH/2)):
    _blk('PB_TrayRib_%d'%k,xc-(PITCH-CH)/2,xc+(PITCH-CH)/2,BOT+0.0010,ZP0-0.0034,BY-0.0006,mB)
_blk('PB_TrayPlat',-TW+0.0004,TW-0.0004,ZP0,ZP1,BY-0.0011,bpy.data.materials['PB_Ledge'])
SW=BW+0.0004
for k,xc in enumerate((PITCH/2,-PITCH/2)):
    _blk('PB_TrayFinger_%d'%k,xc-(PITCH-SW)/2,xc+(PITCH-SW)/2,ZP1-0.0003,TOP,BY-0.0011,bpy.data.materials['PB_Ledge'])
_cyl('PB_TrayScrew',0.0011,0.0006,(0.0,BY-0.0011,(ZP0+ZP1)/2),'Y',bpy.data.materials['PB_Recess'],seg=32)

# ---- RETIME (Vu: the plug-in was too slow): compress everything after frame 560 to 60 % of its length IN the animation,
# so motion stays smooth (no dropped frames). 700 -> 644. Render 488-644.
T0=560.0; K=0.60
def _rt(x): return T0+(x-T0)*K if x>T0 else x
for a in bpy.data.actions:
    for fc in a.fcurves:
        for kp in fc.keyframe_points:
            for attr in ('co','handle_left','handle_right'):
                v=getattr(kp,attr); nx=_rt(v[0])
                if attr!='co' and v[0]<=T0 and kp.co[0]>T0: nx=v[0]
                setattr(kp,attr,(nx,v[1]))
        fc.update()
sc.frame_end=644
