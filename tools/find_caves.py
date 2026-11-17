"""Searches the baked heights for good cave sites: sloping open ground clear of
roads and buildings, with enough hill above for a cavern 35 m under the
ground. Prints one site per region; caves.gd holds the ones chosen.

    python tools/find_caves.py
"""
import numpy as np, math, json
from PIL import Image
import os
D=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'map_data') + os.sep
co=np.array(Image.open(D+'terrain_coarse.png').convert('RGB')).astype(np.int64)
de=np.array(Image.open(D+'terrain_detail.png').convert('RGB')).astype(np.int64)
ch=(co[:,:,0]*256+co[:,:,1])/20.0-300.0; ck=co[:,:,2]%8
dh=(de[:,:,0]*256+de[:,:,1])/100.0-200.0; dk=de[:,:,2]%8
CO=(-25664.0,-34912.0); CS=16.0; DO=(-7636.0,-3872.0); DS=4.0
LAKE=-20.4
def bil(a,gx,gz):
    c=int(gx); r=int(gz); fx=gx-c; fz=gz-r
    return (a[r,c]*(1-fx)+a[r,c+1]*fx)*(1-fz)+(a[r+1,c]*(1-fx)+a[r+1,c+1]*fx)*fz
def H(x,z):
    gx=(x-DO[0])/DS; gz=(z-DO[1])/DS
    if 0<=gx<=dh.shape[1]-1.001 and 0<=gz<=dh.shape[0]-1.001: return bil(dh,gx,gz)
    gx=min(max((x-CO[0])/CS,0),ch.shape[1]-1.001); gz=min(max((z-CO[1])/CS,0),ch.shape[0]-1.001)
    return bil(ch,gx,gz)
def K(x,z):
    gx=(x-DO[0])/DS; gz=(z-DO[1])/DS
    if 0<=gx<=dh.shape[1]-1.001 and 0<=gz<=dh.shape[0]-1.001: return dk[int(gz+.5),int(gx+.5)]
    gx=(x-CO[0])/CS; gz=(z-CO[1])/CS
    return ck[int(gz+.5),int(gx+.5)]
WALL=(-11520.0,-27648.0,17408.0,22528.0)
def made_near(x,z,r=250):
    for dx in range(-int(r),int(r)+1,50):
        for dz in range(-int(r),int(r)+1,50):
            if K(x+dx,z+dz) in (1,2,3,4,5): return True
    return False
def plan(E,theta,R,slope,cav):
    """returns dict or None"""
    Rx,Ry,Rz=cav
    d=(math.cos(theta),math.sin(theta))
    yE=H(*E)
    start_y=yE-R*0.3
    # iterate cavern placement
    L=300.0
    for it in range(6):
        cx=E[0]+d[0]*(L+Rz*0.8); cz=E[1]+d[1]*(L+Rz*0.8)
        gmin=1e9
        for a in range(0,360,20):
            for f in (0,0.5,1.0,1.2):
                gmin=min(gmin,H(cx+math.cos(math.radians(a))*Rx*f, cz+math.sin(math.radians(a))*Rz*f))
        cy=gmin-Ry-35.0
        yend=cy-Ry*0.3
        L=max((start_y-yend)/slope,120.0)
    if L>1400: return None
    # check tunnel
    n=int(L/6)
    entry_end=None
    for i in range(n+1):
        t=i/n; x=E[0]+d[0]*L*t; z=E[1]+d[1]*L*t; y=start_y-(start_y-yend)*t
        g=H(x,z)
        if K(x,z)==5 and y+R>LAKE-2: return None
        ceil=y+R*0.85
        if entry_end is None:
            if ceil<g-1.0: entry_end=L*t
        else:
            if ceil>g-6.0: return None
    if entry_end is None or entry_end>140: return None
    # cavern below lake bed etc: fine. Check cavern top under ground
    return dict(entrance=[round(E[0],1),round(E[1],1)],heading=round(math.degrees(theta),1),tunnel=round(L),
                cavern=[round(cx,1),round(cy,1),round(cz,1)],depth=round(yE-cy),entry=round(entry_end))
rng=np.random.default_rng(3)
found=[]
def try_region(name,x0,x1,z0,z1,tries=4000,R=14.0,cav=(170,60,130)):
    best=None
    for k in range(tries):
        x=rng.uniform(x0,x1); z=rng.uniform(z0,z1)
        if not(WALL[0]+1500<x<WALL[2]-1500 and WALL[1]+1500<z<WALL[3]-1500): continue
        if K(x,z)!=0: continue
        y=H(x,z)
        if y<LAKE+25: continue
        sx=(H(x+6,z)-H(x-6,z))/12; sz=(H(x,z+6)-H(x,z-6))/12
        s=math.hypot(sx,sz)
        if not(0.08<s<0.45): continue
        if made_near(x,z): continue
        # tunnel goes into the hill: uphill direction
        theta=math.atan2(sz,sx)
        for dth in (0,0.4,-0.4,0.8,-0.8):
            p=plan((x,z),theta+dth,R,0.32,cav)
            if p:
                p['name']=name; p['slope']=round(s,2)
                if best is None or p['tunnel']<best['tunnel']: best=p
                break
        if best and best['tunnel']<500: break
    return best
regions=[('Wild Horse Island',-1200,1500,-600,2300),
 ('Mission Range north',13000,16500,-16000,-6000),
 ('Mission Range south',13000,16500,4000,14000),
 ('Salish hills west',-9500,-6000,-10000,0),
 ('Big Arm hills',-9000,-5500,3000,11000),
 ('Somers ridge',-9000,-4000,-25000,-19000)]
for r in regions:
    b=try_region(*r)
    print(json.dumps(b))
