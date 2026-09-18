"""fit-moons.py -- fit the moons' orbits to JPL Horizons; writes src/moon-elements.lisp.

    python3 tools/fit-moons.py        (from the project directory; needs numpy)

Fetches Horizons state vectors of each moon relative to its planet (ICRF) at
80-odd dates log-spaced about J2000 out to +-150 years, and 40 more at random
for measuring. Each state becomes osculating elements in the moon's reference
plane; the node, the longitude of periapsis and the mean longitude are
unwrapped outwards from J2000 and fitted by least squares -- lines, and a
quadratic for the longitude -- and for the moons in resonance a libration
with its period searched. Prints the error over the measuring dates.
"""
import json, os, random, urllib.parse, urllib.request
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "moon-states.json")
MOONS = {"Phobos":(401,499),"Deimos":(402,499),"Io":(501,599),"Europa":(502,599),"Ganymede":(503,599),
 "Callisto":(504,599),"Mimas":(601,699),"Enceladus":(602,699),"Tethys":(603,699),"Dione":(604,699),
 "Rhea":(605,699),"Titan":(606,699),"Iapetus":(608,699),"Miranda":(705,799),"Ariel":(701,799),
 "Umbriel":(702,799),"Titania":(703,799),"Oberon":(704,799),"Triton":(801,899),"Charon":(901,999)}

def fetch(cmd, center, times):
    q = {"format":"text","COMMAND":"'%d'"%cmd,"CENTER":"'500@%d'"%center,"EPHEM_TYPE":"'VECTORS'",
         "REF_PLANE":"'FRAME'","REF_SYSTEM":"'ICRF'","TLIST":" ".join("'%.4f'"%t for t in times),
         "TLIST_TYPE":"'JD'","TIME_TYPE":"'TT'","VEC_TABLE":"'2'","OUT_UNITS":"'KM-S'",
         "CSV_FORMAT":"'YES'","OBJ_DATA":"'NO'"}
    text = urllib.request.urlopen(urllib.request.Request(
        "https://ssd.jpl.nasa.gov/api/horizons.api", data=urllib.parse.urlencode(q).encode()),
        timeout=120).read().decode()
    body = text[text.index("$$SOE")+5:text.index("$$EOE")].strip().split("\n")
    return [[float(x) for i, x in enumerate(l.split(",")) if i in (0,2,3,4,5,6,7)] for l in body]

if not os.path.exists(CACHE):
    offsets = [0.0]; d = 0.05
    while d < 54750: offsets += [d, -d]; d *= 1.35
    fit_times = sorted(2451545.0 + o for o in offsets + [54750, -54750])
    random.seed(7)
    test_times = sorted(round(random.uniform(2396758.5, 2506331.5), 3) for _ in range(40))
    states = {n: {"fit": fetch(c, p, fit_times), "test": fetch(c, p, test_times)}
              for n, (c, p) in MOONS.items()}
    json.dump(states, open(CACHE, "w"))
S = json.load(open(CACHE))
D2R=np.pi/180
# pole (RA, Dec) of each moon's reference plane: JPL's Laplace poles, or the
# IAU pole of the planet for the moons JPL gives against the equator.
POLE={"Phobos":(317.7,52.9),"Deimos":(316.6,53.5),"Io":(268.1,64.5),"Europa":(268.1,64.5),
 "Ganymede":(268.2,64.6),"Callisto":(268.7,64.8),"Mimas":(40.6,83.5),"Enceladus":(40.6,83.5),
 "Tethys":(40.6,83.5),"Dione":(40.6,83.5),"Rhea":(40.6,83.5),"Titan":(36.4,84.0),"Iapetus":(288.7,78.9),
 "Miranda":(77.311,15.175),"Ariel":(77.311,15.175),"Umbriel":(77.311,15.175),"Titania":(77.311,15.175),
 "Oberon":(77.311,15.175),"Triton":(299.8,43.1),"Charon":(132.993,-6.163)}
GM={"Mars":42828.375816,"Jupiter":126686531.9,"Saturn":37931206.23,"Uranus":5793951.3,"Neptune":6835100.0,"Pluto":869.6}
PARENT={"Phobos":"Mars","Deimos":"Mars","Io":"Jupiter","Europa":"Jupiter","Ganymede":"Jupiter","Callisto":"Jupiter",
 "Mimas":"Saturn","Enceladus":"Saturn","Tethys":"Saturn","Dione":"Saturn","Rhea":"Saturn","Titan":"Saturn","Iapetus":"Saturn",
 "Miranda":"Uranus","Ariel":"Uranus","Umbriel":"Uranus","Titania":"Uranus","Oberon":"Uranus","Triton":"Neptune","Charon":"Pluto"}
GMMOON={"Io":5959.9,"Europa":3202.7,"Ganymede":9887.8,"Callisto":7179.3,"Titan":8978.1,"Triton":1428.5,"Charon":106.1}
P0={"Phobos":0.3189,"Deimos":1.2624,"Io":1.769,"Europa":3.551,"Ganymede":7.155,"Callisto":16.689,"Mimas":0.9424,
 "Enceladus":1.3702,"Tethys":1.8878,"Dione":2.7369,"Rhea":4.5175,"Titan":15.945,"Iapetus":79.33,"Miranda":1.4135,
 "Ariel":2.5204,"Umbriel":4.1442,"Titania":8.7059,"Oberon":13.4632,"Triton":-5.877,"Charon":6.3872}
def basis(ra,dec):
    a,d=ra*D2R,dec*D2R
    n=np.array([-np.sin(a),np.cos(a),0]); y=np.array([-np.sin(d)*np.cos(a),-np.sin(d)*np.sin(a),np.cos(d)])
    p=np.array([np.cos(d)*np.cos(a),np.cos(d)*np.sin(a),np.sin(d)])
    return np.array([n,y,p])
def elements(r,v,mu):
    h=np.cross(r,v); hn=np.linalg.norm(h); rn=np.linalg.norm(r)
    i=np.arccos(h[2]/hn); node=np.arctan2(h[0],-h[1])
    nhat=np.array([np.cos(node),np.sin(node),0]); what=h/hn
    ev=((v@v-mu/rn)*r-(r@v)*v)/mu; e=np.linalg.norm(ev)
    m=np.cross(what,nhat)
    w=np.arctan2(ev@m,ev@nhat)
    ehat=ev/e; q=np.cross(what,ehat)
    nu=np.arctan2(r@q,r@ehat)
    E=2*np.arctan(np.sqrt((1-e)/(1+e))*np.tan(nu/2)); M=E-e*np.sin(E)
    a=1/(2/rn-(v@v)/mu)
    return a,e,i,node,w,M
def unwrap_fit(t,ang,deg,rate0):
    order=np.argsort(np.abs(t)); tt=[];aa=[]
    coef=None
    for k in order:
        x=t[k]; y=ang[k]
        if not tt: pred=y
        elif coef is None: 
            j=int(np.argmin(np.abs(np.array(tt)-x))); pred=aa[j]+rate0*(x-tt[j])
        else: pred=np.polyval(coef,x)
        y=y+360*np.round((pred-y)/360)
        tt.append(x); aa.append(y)
        span=max(tt)-min(tt)
        dg=0 if len(tt)<2 else (1 if (len(tt)<6 or span<400) else deg)
        if len(tt)>=2: coef=np.polyfit(tt,aa,dg if dg>0 else 1)
    return np.polyfit(tt,aa,deg), np.array(tt), np.array(aa)
def lib(p,t):
    if not p.get('lib'): return 0*t
    P,A,B=p['lib']; return A*np.sin(2*np.pi*t/P)+B*np.cos(2*np.pi*t/P)
def fit_libration(t,L,pL):
    """Refit L as a quadratic plus one sinusoid, the period searched."""
    best=None
    for P in np.linspace(3650,40000,700):
        X=np.column_stack([t*t,t,np.ones_like(t),np.sin(2*np.pi*t/P),np.cos(2*np.pi*t/P)])
        c,*_=np.linalg.lstsq(X,L,rcond=None); r=np.sum((X@c-L)**2)
        if best is None or r<best[0]: best=(r,P,c)
    r,P,c=best
    return np.array(c[:3]),(float(P),float(c[3]),float(c[4]))
def model(p,t):
    node=np.polyval(p['node'],t); peri=np.polyval(p['peri'],t); L=np.polyval(p['L'],t)+lib(p,t)
    w=(peri-node)*D2R; Om=node*D2R; M=((L-peri+180)%360-180)*D2R; i=p['i']*D2R; e=p['e']; a=p['a']
    E=M.copy()
    for _ in range(30): E=E-(E-e*np.sin(E)-M)/(1-e*np.cos(E))
    xp=a*(np.cos(E)-e); yp=a*np.sqrt(1-e*e)*np.sin(E)
    cw,sw,cn,sn,ci,si=np.cos(w),np.sin(w),np.cos(Om),np.sin(Om),np.cos(i),np.sin(i)
    return np.array([(cw*cn-sw*sn*ci)*xp-(sw*cn+cw*sn*ci)*yp,(cw*sn+sw*cn*ci)*xp+(cw*cn*ci-sw*sn)*yp,sw*si*xp+cw*si*yp])
res={}
for name,data in S.items():
    B=basis(*POLE[name]); mu=GM[PARENT[name]]+GMMOON.get(name,0)
    f=np.array(data['fit']); t=f[:,0]-2451545.0
    els=[elements(B@row[1:4],B@row[4:7],mu) for row in f]
    a,e,i,node,w,M=map(np.array,zip(*els))
    node_d=node/D2R; peri_d=(node+w)/D2R; L_d=(node+w+M)/D2R
    n0=360/P0[name]
    pL,tt_,aa_=unwrap_fit(t,L_d,2,n0)
    libration=None
    if name in ("Mimas","Tethys","Miranda"):
        # Unwrap again against the libration-aware model until it settles.
        for _ in range(4):
            pL,libration=fit_libration(tt_,aa_,pL)
            pred=np.polyval(pL,tt_)+libration[1]*np.sin(2*np.pi*tt_/libration[0])+libration[2]*np.cos(2*np.pi*tt_/libration[0])
            aa_=aa_+360*np.round((pred-aa_)/360)
    pP,_,_=unwrap_fit(t,peri_d,1,0.0)
    pN,_,_=unwrap_fit(t,node_d,1,0.0)
    p={'a':float(np.median(a)),'e':float(np.median(e)),'i':float(np.median(i/D2R)),'node':pN,'peri':pP,'L':pL,'lib':libration}
    tst=np.array(data['test']); tt=tst[:,0]-2451545.0
    obs=np.array([B@row[1:4] for row in tst]).T
    mod=model(p,tt)
    cosang=np.sum(obs*mod,0)/np.linalg.norm(obs,axis=0)/np.linalg.norm(mod,axis=0)
    err=np.degrees(np.arccos(np.clip(cosang,-1,1)))
    print("%-10s max %7.3f  median %6.3f deg   e %.4f i %.3f  L' %.6f deg/d %s" % (name,err.max(),np.median(err),p['e'],p['i'],pL[1],libration and "libration %.1f yr %.1f deg"%(libration[0]/365.25,np.hypot(libration[1],libration[2])) or ""))
    res[name]={'pole':POLE[name],'a_km':p['a'],'e':p['e'],'i':p['i'],'node':[float(x) for x in pN[::-1]],'peri':[float(x) for x in pP[::-1]],'L':[float(x) for x in pL[::-1]],'lib':libration,'max_err':float(err.max())}

LOOK = {"Phobos":("Mars",11.3,"0.56 0.50 0.45"),"Deimos":("Mars",6.2,"0.60 0.55 0.50"),
 "Io":("Jupiter",1821.6,"0.95 0.86 0.45"),"Europa":("Jupiter",1560.8,"0.86 0.80 0.70"),
 "Ganymede":("Jupiter",2634.1,"0.72 0.68 0.62"),"Callisto":("Jupiter",2410.3,"0.56 0.51 0.46"),
 "Mimas":("Saturn",198.2,"0.84 0.84 0.84"),"Enceladus":("Saturn",252.1,"0.95 0.95 0.97"),
 "Tethys":("Saturn",531.1,"0.88 0.88 0.88"),"Dione":("Saturn",561.4,"0.85 0.85 0.86"),
 "Rhea":("Saturn",763.8,"0.82 0.82 0.83"),"Titan":("Saturn",2574.7,"0.92 0.70 0.36"),
 "Iapetus":("Saturn",734.5,"0.70 0.64 0.58"),"Miranda":("Uranus",235.8,"0.72 0.72 0.74"),
 "Ariel":("Uranus",578.9,"0.76 0.76 0.78"),"Umbriel":("Uranus",584.7,"0.60 0.60 0.62"),
 "Titania":("Uranus",788.4,"0.74 0.72 0.72"),"Oberon":("Uranus",761.4,"0.70 0.68 0.68"),
 "Triton":("Neptune",1353.4,"0.86 0.76 0.76"),"Charon":("Pluto",606.0,"0.66 0.64 0.62")}

def lisp(x):
    s = repr(float(x))
    return s.replace("e", "d") if "e" in s else s + "d0"

HEADER = """;;;; moon-elements.lisp -- the moons' orbits, fitted to JPL Horizons.
;;;;
;;;; GENERATED by tools/fit-moons.py from Horizons state vectors (relative to
;;;; each planet's centre, ICRF) at 80 dates from 1850 to 2150, log-spaced
;;;; about J2000. Each state is turned into osculating elements in the moon's
;;;; reference plane -- the Laplace plane JPL gives for it, or the planet's
;;;; equator -- and the angles are unwrapped and fitted by least squares:
;;;; the node and the longitude of periapsis as lines, the mean longitude as
;;;; a quadratic, plus, for the moons in resonance, one libration.
;;;;
;;;; Each entry: name, parent, radius km, colour, then
;;;;   :pole (ra dec)       the reference plane's pole, ICRF degrees
;;;;   :a :e :i             km, -, degrees
;;;;   :node :peri :l       polynomial coefficients in days from J2000 TT,
;;;;                        constant first, degrees
;;;;   :libration           (period days, sine amplitude, cosine amplitude) in L
;;;;   :error               the largest error in direction seen over 40
;;;;                        other dates in 1850 -- 2150, degrees

(in-package #:solar-system.core)

(defparameter *moon-elements*
  '("""
rows = []
for n, (parent, r, colour) in LOOK.items():
    p = res[n]
    lib = "(%s %s %s)" % tuple(lisp(x) for x in p["lib"]) if p["lib"] else "nil"
    rows.append('''    ("%s" "%s" %s #(%s)
     :pole (%s %s) :a %s :e %s :i %s
     :node (%s) :peri (%s)
     :l (%s)
     :libration %s :error %s)''' % (n, parent, lisp(r), colour, lisp(p["pole"][0]), lisp(p["pole"][1]),
        lisp(p["a_km"]), lisp(p["e"]), lisp(p["i"]), " ".join(lisp(x) for x in p["node"]),
        " ".join(lisp(x) for x in p["peri"]), " ".join(lisp(x) for x in p["L"]), lib, "%.3fd0" % p["max_err"]))
with open(os.path.join(HERE, "..", "src", "moon-elements.lisp"), "w") as out:
    out.write(HEADER + "\n" + "\n".join(rows) + "))\n")
