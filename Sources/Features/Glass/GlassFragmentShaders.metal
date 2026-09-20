#include <metal_stdlib>
#include "GlassCrackShading.h"
#include <TargetConditionals.h>
#if !TARGET_OS_SIMULATOR
#include <metal_raytracing>
#endif
using namespace metal;

struct RayTriangle { float4 a,b,c,na,nb,nc; };
struct RayNode { float4 minimum,maximum; uint4 links; };
struct RayUniforms {
    float4 viewport; // trace width, height, camera half-height, pattern
    float4 optics; // IOR, visible, light angle, max internal hits
    uint4 sampling; // sample index, maximum samples, dispersion, crack count
    float4x4 rotation;
    float4 effect; // visibility, joined/rest pose
};
struct RayHit { float distance; uint primitive; float2 barycentric; uint instance; };
constant float rayEpsilon = 0.001;

static float boxEntry(float3 origin,float3 direction,float3 low,float3 high,float limit) {
    float3 safe = select(float3(1e-12),direction,abs(direction)>1e-12);
    float3 a=(low-origin)/safe, b=(high-origin)/safe;
    float3 near=min(a,b),far=max(a,b);
    float lo=max(near.x,max(near.y,near.z));
    float hi=min(far.x,min(far.y,far.z));
    return hi>=max(lo,rayEpsilon) && lo<limit ? max(lo,0.0) : INFINITY;
}

struct FragmentInstance {
    float4x4 transform;
    float4 originalCenter;
    uint4 links; // local BVH root, triangle offset, unused, unused
};
struct FragmentIntersector {
    device const RayTriangle *triangles;
    device const RayNode *nodes;
    device const RayNode *top;
    device const FragmentInstance *instances;
    bool joined;
    RayHit intersect(float3 origin,float3 direction) const {
        RayHit best={INFINITY,0,float2(0),0};
        uint stack[32],count=1; stack[0]=0;
        while(count) {
            RayNode node=top[stack[--count]];
            if(!isfinite(boxEntry(origin,direction,node.minimum.xyz,node.maximum.xyz,best.distance))) continue;
            if(node.links.y==0) { stack[count++]=node.links.x; stack[count++]=node.links.z; continue; }
            uint instanceID=node.links.x;
            FragmentInstance instance=instances[instanceID];
            float3x3 rotation=float3x3(instance.transform[0].xyz,instance.transform[1].xyz,instance.transform[2].xyz);
            float3 o=transpose(rotation)*(origin-instance.transform[3].xyz),d=transpose(rotation)*direction;
            uint local[32],n=1; local[0]=instance.links.x;
            while(n) {
                RayNode b=nodes[local[--n]];
                if(!isfinite(boxEntry(o,d,b.minimum.xyz,b.maximum.xyz,best.distance))) continue;
                if(!b.links.y) { local[n++]=b.links.x; local[n++]=b.links.z; continue; }
                for(uint i=0;i<b.links.y;++i) {
                    uint id=b.links.x+i; RayTriangle t=triangles[id];
                    if(joined && t.na.w<0.5) continue;
                    float3 e1=t.b.xyz-t.a.xyz,e2=t.c.xyz-t.a.xyz,p=cross(d,e2);
                    float det=dot(e1,p); if(abs(det)<1e-10) continue;
                    float3 delta=o-t.a.xyz; float u=dot(delta,p)/det;
                    if(u<0 || u>1) continue;
                    float3 q=cross(delta,e1); float v=dot(d,q)/det, distance=dot(e2,q)/det;
                    if(v>=0 && u+v<=1 && distance>rayEpsilon && distance<best.distance) best={distance,id,float2(u,v),instanceID};
                }
            }
        }
        return best;
    }
};
#if !TARGET_OS_SIMULATOR
struct FragmentHardwareIntersector {
    raytracing::instance_acceleration_structure acceleration;
    device const FragmentInstance *instances;
    device const RayTriangle *triangles;
    bool joined;
    RayHit intersect(float3 origin,float3 direction) const {
        raytracing::ray ray(origin,direction,rayEpsilon,INFINITY);
        raytracing::intersector<raytracing::triangle_data,raytracing::instancing> query;
        query.assume_geometry_type(raytracing::geometry_type::triangle);
        query.force_opacity(raytracing::forced_opacity::opaque);
        for(uint skip=0;skip<256;++skip) {
            auto hit=query.intersect(ray,acceleration);
            if(hit.type==raytracing::intersection_type::none) return {INFINITY,0,float2(0),0};
            uint primitive=instances[hit.instance_id].links.y+hit.primitive_id;
            if(!joined || triangles[primitive].na.w>0.5) return {hit.distance,primitive,hit.triangle_barycentric_coord,hit.instance_id};
            // At the exact rest pose cut faces touch: their union is still one optical volume.
            ray.min_distance=hit.distance+rayEpsilon;
        }
        return {INFINITY,0,float2(0),0};
    }
};
#endif

static float lineCoverage(float distance,float width,float aa) { return 1-smoothstep(width,width+aa,distance); }
static float3 rayPattern(float2 p,int pattern,float aa) {
    if(pattern==3) return float3(0.009,0.012,0.013);
    float3 paper=float3(0.89,0.91,0.86),green=float3(0.16,0.34,0.27),orange=float3(0.77,0.26,0.12);
    float3 color=paper;
    if(pattern==0) {
        color=mix(color,orange,1-smoothstep(57.0,57.0+aa,length(p-float2(51,93))));
        float radius=length(p-float2(-66,-55));
        float ring=lineCoverage(abs(fract(radius/22)-0.5)*22,3,aa);
        color=mix(color,green,ring*(1-smoothstep(163.0,163.0+aa,radius)));
        float2 grid=abs(fract((p+12)/24)-0.5)*24;
        color=mix(color,green,lineCoverage(min(grid.x,grid.y),0.28,aa)*0.18);
    } else if(pattern==1) {
        float2 tile=(p+12)/24;
        float2 soft=smoothstep(float2(0),float2(aa/24),fract(tile));
        float checker=fmod(abs(floor(tile.x)+floor(tile.y)),2.0);
        color=mix(paper,green,mix(1-checker,checker,soft.x*soft.y));
    } else {
        float2 grid=abs(fract((p+10)/20)-0.5)*20;
        color=mix(color,green,lineCoverage(min(grid.x,grid.y),0.65,aa)*0.85);
        color=mix(color,orange,lineCoverage(min(abs(p.x),abs(p.y)),1.2,aa));
    }
    return color;
}

// A finite rectangular emitter in front of the glass. Reflections respond to hit position,
// surface normals and emitter position; no painted highlight or screen-space reflection.
static float3 studio(float3 origin,float3 direction,float angle) {
    float3 ambient=mix(float3(0.07,0.10,0.085),float3(0.32,0.40,0.35),saturate(direction.y*0.5+0.5));
    if(direction.z>0.001) {
        float2 p=(origin+direction*((410-origin.z)/direction.z)).xy;
        float2 center=float2(-175+260*sin(angle),65+90*cos(angle));
        float2 q=abs(p-center)-float2(34,235);
        float lamp=1-smoothstep(-4.0,4.0,max(q.x,q.y));
        float2 q2=abs(p-float2(225,-40))-float2(16,260);
        float fill=1-smoothstep(-3.0,3.0,max(q2.x,q2.y));
        ambient+=float3(7.0,6.6,5.9)*lamp+float3(3.0,3.8,4.0)*fill;
    }
    return ambient;
}
static float fresnelDielectric(float cosine,float etaI,float etaT) {
    float sin2=(etaI/etaT)*(etaI/etaT)*max(0.0,1-cosine*cosine);
    if(sin2>=1) return 1;
    float ct=sqrt(1-sin2);
    float rs=(etaI*cosine-etaT*ct)/(etaI*cosine+etaT*ct);
    float rp=(etaT*cosine-etaI*ct)/(etaT*cosine+etaI*ct);
    return 0.5*(rs*rs+rp*rp);
}
static float3 hitNormal(RayHit hit,device const RayTriangle *triangles) {
    RayTriangle t=triangles[hit.primitive];
    return normalize(t.na.xyz*(1-hit.barycentric.x-hit.barycentric.y)
                     +t.nb.xyz*hit.barycentric.x+t.nc.xyz*hit.barycentric.y);
}

template<typename Intersector>
static float3 outsideRadiance(float3 origin,float3 direction,constant RayUniforms &u,
                             Intersector scene,float3x3 inverse,float aa) {
    if(direction.z>=-0.0001) return studio(origin,direction,u.optics.z);
    float distance=(-240-origin.z)/direction.z;
    if(distance<=0) return studio(origin,direction,u.optics.z);
    float3 p=origin+direction*distance;
    float3 base=rayPattern(p.xy,int(u.viewport.w),aa);
    // A transmission-aware shadow ray to a front light: accumulate actual glass path length.
    float3 lamp=float3(-175+260*sin(u.optics.z),65+90*cos(u.optics.z),410);
    float3 shadowDirection=normalize(lamp-p);
    float3 localOrigin=inverse*p,localDirection=inverse*shadowDirection;
    RayHit a=scene.intersect(localOrigin,localDirection);
    float3 transmittance=float3(1);
    if(isfinite(a.distance) && a.distance<length(lamp-p)) {
        float3 entry=localOrigin+localDirection*(a.distance+0.035);
        RayHit b=scene.intersect(entry,localDirection);
        if(isfinite(b.distance)) transmittance=exp(-float3(0.0035,0.001,0.002)*b.distance)*0.91;
    }
    return base*(0.30+0.70*transmittance);
}

template<typename Intersector>
static float3 traceFragment(float2 uv,constant RayUniforms &u,device const RayTriangle *triangles,
                           Intersector scene,device const FragmentInstance *instances,texture2d<float> material,device const float4 *cracks,float ior) {
    float3x3 pane=float3x3(u.rotation[0].xyz,u.rotation[1].xyz,u.rotation[2].xyz), inverse=transpose(pane);
    float2 xy=(uv-0.5)*float2(2*u.viewport.x/u.viewport.y,-2)*u.viewport.z;
    float aa=max(0.2,2*u.viewport.z/u.viewport.y);
    float3 background=rayPattern(xy,int(u.viewport.w),aa);
    if(u.effect.x<=0) return background;
    float3 origin=inverse*float3(xy,600),direction=inverse*float3(0,0,-1);
    float3 result=0,weight=1;
    bool inside=false, scar=false;
    float2 scarPoint=0; float3 scarView=0,scarLight=0;
    for(uint bounce=0;bounce<uint(u.optics.w);++bounce) {
        RayHit hit=scene.intersect(origin,direction);
        if(!isfinite(hit.distance)) {
            result+=weight*outsideRadiance(pane*origin,pane*direction,u,scene,inverse,aa); break;
        }
        FragmentInstance instance=instances[hit.instance];
        float3x3 rotation=float3x3(instance.transform[0].xyz,instance.transform[1].xyz,instance.transform[2].xyz);
        float3 point=origin+direction*hit.distance;
        float3 local=transpose(rotation)*(point-instance.transform[3].xyz);
        float3 normal=rotation*hitNormal(hit,triangles);
        bool entering=dot(direction,normal)<0;
        if(inside) weight*=exp(-float3(0.0035,0.001,0.002)*hit.distance);
        float3 facing=entering ? normal:-normal;
        float etaI=entering ? 1:ior,etaT=entering ? ior:1;
        float f=fresnelDielectric(saturate(-dot(direction,facing)),etaI,etaT);
        float3 transmitted=refract(direction,facing,etaI/etaT);
        if(f>=0.9999) {
            direction=reflect(direction,facing);
            if(u.sampling.y==0) { result+=weight*outsideRadiance(pane*point,pane*direction,u,scene,inverse,aa); break; }
        }
        else {
            result+=weight*f*outsideRadiance(pane*point,pane*reflect(direction,facing),u,scene,inverse,aa);
            weight*=1-f; direction=transmitted; inside=entering;
        }
        if(bounce==0) {
            RayTriangle t=triangles[hit.primitive];
            if(t.na.w>0.5) {
                float3 view=transpose(rotation)*inverse*float3(0,0,1);
                float3 light=transpose(rotation)*inverse*normalize(float3(-175+260*sin(u.optics.z),65+90*cos(u.optics.z),410));
                // Add the original-pane surface scar without moving the UV with the fragment.
                scar=true; scarPoint=local.xy+instance.originalCenter.xy; scarView=view; scarLight=light;
            } else result+=float3(0.05,0.075,0.065)*(0.35+0.65*abs(dot(normal,normalize(float3(-0.3,0.5,1)))));
        }
        origin=point+direction*0.002;
    }
    if(scar) {
        result=shadeGlassCracks(result,scarPoint,aa,cracks,u.sampling.w);
        result=shadeCrackNetwork(result,scarPoint,scarView,scarLight,material);
    }
    return mix(background,result,u.effect.x);
}


template<typename Intersector>
static float3 fragmentSample(float2 uv,constant RayUniforms &u,device const RayTriangle *triangles,
                            Intersector scene,device const FragmentInstance *instances,texture2d<float> material,device const float4 *cracks) {
    if(u.sampling.z) {
        return float3(traceFragment(uv,u,triangles,scene,instances,material,cracks,u.optics.x-0.006).r,
                      traceFragment(uv,u,triangles,scene,instances,material,cracks,u.optics.x).g,
                      traceFragment(uv,u,triangles,scene,instances,material,cracks,u.optics.x+0.009).b);
    }
    return traceFragment(uv,u,triangles,scene,instances,material,cracks,u.optics.x);
}

kernel void glassFragmentsSoftware(texture2d<float,access::write> output [[texture(0)]],
    texture2d<float> material [[texture(1)]], constant RayUniforms &u [[buffer(0)]],
    device const RayTriangle *triangles [[buffer(1)]],device const RayNode *nodes [[buffer(2)]],
    device const RayNode *top [[buffer(3)]],device const FragmentInstance *instances [[buffer(4)]],
    device const float4 *cracks [[buffer(5)]], uint2 pixel [[thread_position_in_grid]]) {
    if(any(pixel>=uint2(u.viewport.xy))) return;
    FragmentIntersector scene={triangles,nodes,top,instances,u.effect.y>0.5};
    output.write(float4(fragmentSample((float2(pixel)+0.5)/u.viewport.xy,u,triangles,scene,instances,material,cracks),1),pixel);
}
#if !TARGET_OS_SIMULATOR
kernel void glassFragmentsHardware(texture2d<float,access::write> output [[texture(0)]],
    texture2d<float> material [[texture(1)]], constant RayUniforms &u [[buffer(0)]],
    device const RayTriangle *triangles [[buffer(1)]],
    raytracing::instance_acceleration_structure acceleration [[buffer(3)]],
    device const FragmentInstance *instances [[buffer(4)]], device const float4 *cracks [[buffer(5)]], uint2 pixel [[thread_position_in_grid]]) {
    if(any(pixel>=uint2(u.viewport.xy))) return;
    FragmentHardwareIntersector scene={acceleration,instances,triangles,u.effect.y>0.5};
    output.write(float4(fragmentSample((float2(pixel)+0.5)/u.viewport.xy,u,triangles,scene,instances,material,cracks),1),pixel);
}
#endif
