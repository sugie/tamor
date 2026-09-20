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
};
struct RayHit { float distance; uint primitive; float2 barycentric; };
constant float rayEpsilon = 0.012;

static float boxEntry(float3 origin,float3 direction,float3 low,float3 high,float limit) {
    float3 safe = select(float3(1e-12),direction,abs(direction)>1e-12);
    float3 a=(low-origin)/safe, b=(high-origin)/safe;
    float3 near=min(a,b),far=max(a,b);
    float lo=max(near.x,max(near.y,near.z));
    float hi=min(far.x,min(far.y,far.z));
    return hi>=max(lo,rayEpsilon) && lo<limit ? max(lo,0.0) : INFINITY;
}

struct SoftwareIntersector {
    device const RayTriangle *triangles;
    device const RayNode *nodes;
    RayHit intersect(float3 origin,float3 direction) const {
        RayHit hit={INFINITY,0,float2(0)};
        uint stack[32]; uint count=1; stack[0]=0;
        while(count) {
            uint index=stack[--count];
            RayNode node=nodes[index];
            if (!isfinite(boxEntry(origin,direction,node.minimum.xyz,node.maximum.xyz,hit.distance))) continue;
            if (node.links.y) {
                for(uint i=0;i<node.links.y;++i) {
                    uint primitive=node.links.x+i;
                    RayTriangle triangle=triangles[primitive];
                    float3 e1=triangle.b.xyz-triangle.a.xyz,e2=triangle.c.xyz-triangle.a.xyz;
                    float3 p=cross(direction,e2);
                    float det=dot(e1,p);
                    if(abs(det)<1e-9) continue;
                    float3 delta=origin-triangle.a.xyz;
                    float u=dot(delta,p)/det;
                    if(u<0 || u>1) continue;
                    float3 q=cross(delta,e1);
                    float v=dot(direction,q)/det;
                    float distance=dot(e2,q)/det;
                    if(v>=0 && u+v<=1 && distance>rayEpsilon && distance<hit.distance)
                        hit={distance,primitive,float2(u,v)};
                }
            } else {
                RayNode left=nodes[node.links.x],right=nodes[node.links.z];
                float l=boxEntry(origin,direction,left.minimum.xyz,left.maximum.xyz,hit.distance);
                float r=boxEntry(origin,direction,right.minimum.xyz,right.maximum.xyz,hit.distance);
                // Balanced median BVH has depth < 16; far child is visited last.
                if(l<r) { if(isfinite(r)) stack[count++]=node.links.z; if(isfinite(l)) stack[count++]=node.links.x; }
                else { if(isfinite(l)) stack[count++]=node.links.x; if(isfinite(r)) stack[count++]=node.links.z; }
            }
        }
        return hit;
    }
};

#if !TARGET_OS_SIMULATOR
struct HardwareIntersector {
    raytracing::primitive_acceleration_structure acceleration;
    RayHit intersect(float3 origin,float3 direction) const {
        raytracing::ray ray(origin,direction,rayEpsilon,INFINITY);
        raytracing::intersector<raytracing::triangle_data> query;
        query.assume_geometry_type(raytracing::geometry_type::triangle);
        query.force_opacity(raytracing::forced_opacity::opaque);
        auto result=query.intersect(ray,acceleration);
        if(result.type==raytracing::intersection_type::none) return {INFINITY,0,float2(0)};
        return {result.distance,result.primitive_id,result.triangle_barycentric_coord};
    }
};
#endif

static uint randomBits(thread uint &seed) {
    seed=seed*747796405u+2891336453u;
    uint word=((seed>>((seed>>28u)+4u))^seed)*277803737u;
    return (word>>22u)^word;
}
static float randomValue(thread uint &seed) { return float(randomBits(seed)>>8)/16777216.0; }
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
static float3 traceGlass(float2 uv,constant RayUniforms &u,device const RayTriangle *triangles,
                        Intersector scene,float ior,thread uint &rng,device const float4 *cracks,texture2d<float> material) {
    float3x3 rotation=float3x3(u.rotation[0].xyz,u.rotation[1].xyz,u.rotation[2].xyz);
    float3x3 inverse=transpose(rotation);
    float aspect=u.viewport.x/u.viewport.y;
    float2 worldXY=(uv-0.5)*float2(2*aspect,-2)*u.viewport.z;
    float aa=max(0.2,2*u.viewport.z/u.viewport.y);
    if(u.optics.y<0.5) return rayPattern(worldXY,int(u.viewport.w),aa);
    float3 origin=inverse*float3(worldXY,600),direction=inverse*float3(0,0,-1);
    RayHit entry=scene.intersect(origin,direction);
    if(!isfinite(entry.distance)) return outsideRadiance(float3(worldXY,600),float3(0,0,-1),u,scene,inverse,aa);
    float3 p=origin+direction*entry.distance;
    float2 crackPoint=p.xy;
    float3 normal=hitNormal(entry,triangles);
    // Tiny microfacet perturbation accumulates to a slightly soft polished reflection.
    float2 micro=float2(randomValue(rng)-0.5,randomValue(rng)-0.5)*0.004;
    normal=normalize(normal+float3(micro,0));
    if(dot(normal,direction)>0) normal=-normal;
    float f=fresnelDielectric(saturate(-dot(direction,normal)),1,ior);
    float3 reflection=rotation*reflect(direction,normal);
    float3 radiance=f*outsideRadiance(rotation*p,reflection,u,scene,inverse,aa);
    float3 weight=float3(1-f);
    direction=refract(direction,normal,1/ior);
    origin=p+direction*0.035;
    // Deterministic Fresnel splitting: collect transmitted rays, then follow the remaining
    // internal reflected energy. This keeps thin glass much less noisy than roulette paths.
    for(uint bounce=0;bounce<uint(u.optics.w);++bounce) {
        RayHit hit=scene.intersect(origin,direction);
        if(!isfinite(hit.distance)) break;
        weight*=exp(-float3(0.0035,0.001,0.002)*hit.distance);
        p=origin+direction*hit.distance;
        normal=hitNormal(hit,triangles);
        if(dot(normal,direction)<0) normal=-normal;
        float cosine=saturate(dot(direction,normal));
        float fr=fresnelDielectric(cosine,ior,1);
        float3 transmission=refract(direction,-normal,ior);
        if(fr<0.9999) {
            radiance+=weight*(1-fr)*outsideRadiance(rotation*p,rotation*transmission,u,scene,inverse,aa);
        }
        weight*=fr;
        if(max(weight.x,max(weight.y,weight.z))<0.0005) break;
        direction=reflect(direction,normal);
        origin=p+direction*0.035;
    }
    radiance=shadeGlassCracks(radiance,crackPoint,aa,cracks,u.sampling.w);
    float3 light=inverse*normalize(float3(-175+260*sin(u.optics.z),65+90*cos(u.optics.z),410));
    return shadeCrackNetwork(radiance,crackPoint,inverse*float3(0,0,1),light,material);
}

template<typename Intersector>
static float4 renderSample(uint2 pixel,constant RayUniforms &u,device const RayTriangle *triangles,Intersector scene,
                           device const float4 *cracks,texture2d<float> material) {
    uint rng=pixel.x*1973u+pixel.y*9277u+u.sampling.x*26699u+911u;
    float2 jitter=float2(randomValue(rng),randomValue(rng));
    float2 uv=(float2(pixel)+jitter)/u.viewport.xy;
    float3 color;
    if(u.sampling.z) {
        // Wavelength-dependent IOR (artistic crown-glass approximation).
        color.r=traceGlass(uv,u,triangles,scene,u.optics.x-0.006,rng,cracks,material).r;
        color.g=traceGlass(uv,u,triangles,scene,u.optics.x,rng,cracks,material).g;
        color.b=traceGlass(uv,u,triangles,scene,u.optics.x+0.009,rng,cracks,material).b;
    } else color=traceGlass(uv,u,triangles,scene,u.optics.x,rng,cracks,material);
    return float4(color,1);
}

kernel void glassTraceSoftware(texture2d<float,access::write> accumulation [[texture(0)]],
                               texture2d<float> material [[texture(1)]],
                               texture2d<float,access::read> previousTexture [[texture(2)]],
                               constant RayUniforms &u [[buffer(0)]],
                               device const RayTriangle *triangles [[buffer(1)]],
                               device const RayNode *nodes [[buffer(2)]],device const float4 *cracks [[buffer(4)]],
                               uint2 pixel [[thread_position_in_grid]]) {
    if(any(pixel>=uint2(u.viewport.xy))) return;
    SoftwareIntersector scene={triangles,nodes};
    float4 sample=renderSample(pixel,u,triangles,scene,cracks,material);
    float4 previous=u.sampling.x ? previousTexture.read(pixel) : float4(0);
    accumulation.write(mix(previous,sample,1.0/(float(u.sampling.x)+1)),pixel);
}

#if !TARGET_OS_SIMULATOR
kernel void glassTraceHardware(texture2d<float,access::write> accumulation [[texture(0)]],
                               texture2d<float> material [[texture(1)]],
                               texture2d<float,access::read> previousTexture [[texture(2)]],
                               constant RayUniforms &u [[buffer(0)]],
                               device const RayTriangle *triangles [[buffer(1)]],
                               raytracing::primitive_acceleration_structure acceleration [[buffer(3)]],
                               device const float4 *cracks [[buffer(4)]],
                               uint2 pixel [[thread_position_in_grid]]) {
    if(any(pixel>=uint2(u.viewport.xy))) return;
    HardwareIntersector scene={acceleration};
    float4 sample=renderSample(pixel,u,triangles,scene,cracks,material);
    float4 previous=u.sampling.x ? previousTexture.read(pixel) : float4(0);
    accumulation.write(mix(previous,sample,1.0/(float(u.sampling.x)+1)),pixel);
}
#endif

struct RayDisplayVertex { float4 position [[position]]; float2 uv; };
fragment float4 glassTraceDisplay(RayDisplayVertex in [[stage_in]],texture2d<float> accumulation [[texture(0)]]) {
    constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);
    float3 linear=max(accumulation.sample(s,in.uv).rgb,0.0);
    // Simple shoulder compresses bright emitters while preserving the pale background.
    float3 mapped=linear/(1+linear*0.30);
    return float4(pow(saturate(mapped),float3(1.0/2.2)),1);
}
