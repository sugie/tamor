#include <metal_stdlib>
#include "GlassCrackShading.h"
using namespace metal;

struct StudyUniforms {
    float4 viewport;
    float4 dimensions;
    float4 optics;
    float4x4 rotation;
    float4 lighting;
};
struct StudyVertex { float4 position [[position]]; float2 uv; };
vertex StudyVertex studyVertex(uint id [[vertex_id]]) {
    float2 p[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
    return {float4(p[id],0,1), p[id] * float2(0.5,-0.5) + 0.5};
}

// Fixed, low-frequency waves describe the surface itself, not animated water/noise.
// Their weighted sum is bounded by amplitude (mm). The back remains flat.
static float surfaceHeight(float2 p, float amplitude) {
    return amplitude * (0.50 * sin(p.x * 0.037 + p.y * 0.012 + 0.8)
                       * cos(p.y * 0.029 - 0.4)
                       + 0.30 * sin(p.x * 0.018 - p.y * 0.043 + 1.7)
                       + 0.20 * cos(p.x * 0.061 + p.y * 0.021));
}
static float glassDistance(float3 p, constant StudyUniforms &u) {
    float3 halfSize = u.dimensions.xyz * 0.5;
    p.z -= surfaceHeight(p.xy, u.optics.x) * smoothstep(-halfSize.z, halfSize.z, p.z);
    float3 q = abs(p) - (halfSize - u.dimensions.w);
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - u.dimensions.w;
}
static float3 glassNormal(float3 p, constant StudyUniforms &u) {
    const float e = 0.06;
    return normalize(float3(glassDistance(p+float3(e,0,0),u)-glassDistance(p-float3(e,0,0),u),
                            glassDistance(p+float3(0,e,0),u)-glassDistance(p-float3(0,e,0),u),
                            glassDistance(p+float3(0,0,e),u)-glassDistance(p-float3(0,0,e),u)));
}
static float lineMask(float distance, float width, float aa) {
    return 1.0 - smoothstep(width, width + aa, distance);
}
static float3 backdrop(float2 p, float aa, int pattern) {
    if(pattern==3) return float3(0.009,0.012,0.013);
    const float3 paper = float3(0.92, 0.93, 0.89);
    const float3 green = float3(0.24, 0.42, 0.37);
    const float3 orange = float3(0.81, 0.36, 0.22);
    float3 color = paper;
    if (pattern == 0) {
        // Oversized concentric arcs, an orange disk and fine graph lines.
        float disk = 1.0 - smoothstep(57.0, 57.0+aa, length(p-float2(51,93)));
        color = mix(color, orange, disk);
        float radius = length(p-float2(-66,-55));
        float ring = lineMask(abs(fract(radius/22.0)-0.5)*22.0, 3.0, aa);
        float field = 1.0-smoothstep(163.0,163.0+aa,radius);
        color = mix(color, green, ring*field);
        float2 g = abs(fract((p+12)/24.0)-0.5)*24.0;
        float grid = lineMask(min(g.x,g.y), 0.28, aa);
        color = mix(color, float3(0.43,0.53,0.47), grid*0.26);
    } else if (pattern == 1) {
        float2 cell = floor((p+12)/24.0);
        float checker = fmod(abs(cell.x+cell.y),2.0);
        color = mix(paper, float3(0.32,0.49,0.43), checker);
    } else {
        float2 g = abs(fract((p+10)/20.0)-0.5)*20.0;
        float grid = lineMask(min(g.x,g.y),0.65,aa);
        color = mix(paper,green,grid*0.8);
        float axes = lineMask(min(abs(p.x),abs(p.y)),1.2,aa);
        color = mix(color,orange,axes);
    }
    return color;
}
static float3 environment(float3 ray) {
    float3 c = mix(float3(0.27,0.38,0.35),float3(0.91,0.96,0.94),smoothstep(-0.5,0.8,ray.y));
    float strip = exp(-pow((ray.x+0.30)/0.12,2.0)-pow((ray.y-0.32)/0.8,4.0));
    float window = exp(-pow((ray.x-0.55)/0.23,8.0)-pow((ray.y-0.18)/0.55,8.0));
    return c + float3(1.8)*strip + float3(0.9)*window;
}

fragment float4 studyFragment(StudyVertex in [[stage_in]], constant StudyUniforms &u [[buffer(0)]],
                              device const float4 *cracks [[buffer(1)]], texture2d<float> material [[texture(0)]]) {
    float aspect = u.viewport.x/u.viewport.y;
    float2 worldXY = (in.uv-float2(0.5))*float2(2*aspect,-2)*u.viewport.z;
    float aa = max(0.15,2*u.viewport.z/u.viewport.y);
    int pattern = int(u.viewport.w);
    float3 color = backdrop(worldXY,aa,pattern);
    if (u.optics.z < 0.5) return float4(color,1);
    float3x3 rotation = float3x3(u.rotation[0].xyz,u.rotation[1].xyz,u.rotation[2].xyz);
    float3x3 inverse = transpose(rotation);
    // Orthographic rays preserve a consistent millimetre scale in X and Y.
    float3 origin = inverse * float3(worldXY,600);
    float3 direction = inverse * float3(0,0,-1);
    float3 bound = u.dimensions.xyz*0.5 + float3(0.1,0.1,u.optics.x+0.1);

    // Broad translucent contact shadow. Rotates with the specimen.
    float3 shadowPoint = inverse * float3(worldXY-float2(9,-13),0);
    float2 sd = abs(shadowPoint.xy)-u.dimensions.xy*0.5;
    float shadow = (1-smoothstep(-5.0,22.0,max(sd.x,sd.y)))*0.13;
    color *= 1-shadow;

    float3 safeDirection = select(float3(0.000001),direction,abs(direction)>0.000001);
    float3 t0 = (-bound-origin)/safeDirection;
    float3 t1 = (bound-origin)/safeDirection;
    float3 nearAxis = min(t0,t1), farAxis = max(t0,t1);
    float nearT = max(nearAxis.x,max(nearAxis.y,nearAxis.z));
    float farT = min(farAxis.x,min(farAxis.y,farAxis.z));
    if (nearT > farT || farT < 0) return float4(color,1);

    float t = max(nearT,0.0);
    bool hit = false;
    for (int step=0; step<72; ++step) {
        float distance = glassDistance(origin+direction*t,u);
        if (distance < 0.035) { hit=true; break; }
        t += max(distance*0.75,0.02);
        if (t>farT) break;
    }
    if (!hit) return float4(color,1);
    float3 entry = origin + direction*t;
    float3 normal = glassNormal(entry,u);
    float3 insideDirection = refract(direction,normal,1.0/u.optics.y);
    float3 exitPoint = entry + insideDirection*0.16;
    float travel = 0.16;
    bool exited = false;
    for (int step=0; step<96; ++step) {
        float distance = -glassDistance(exitPoint,u);
        if (distance < 0.025) { exited=true; break; }
        float stride = max(distance*0.75,0.02);
        travel += stride;
        exitPoint += insideDirection*stride;
    }
    float3 exitNormal = glassNormal(exitPoint,u);
    float3 outgoing = refract(insideDirection,-exitNormal,u.optics.y);
    float3 worldExit = rotation*exitPoint;
    float3 worldOutgoing = rotation*outgoing;
    float3 reflected = environment(rotation*reflect(direction,normal));
    float3 transmission;
    if (!exited || dot(outgoing,outgoing)<0.01 || worldOutgoing.z>=-0.001) {
        // Total internal reflection at polished edges; environment approximation.
        transmission = environment(rotation*reflect(insideDirection,exitNormal))*0.65;
    } else {
        // Behind the whole bounding sphere (radius < 210 mm), even at maximum tilt.
        float backgroundT = (-240-worldExit.z)/worldOutgoing.z;
        float2 samplePoint = (worldExit+worldOutgoing*backgroundT).xy;
        transmission = backdrop(samplePoint,aa,pattern);
        // Beer-Lambert absorption: a longer path through the edge looks greener.
        transmission *= exp(-float3(0.0075,0.0018,0.0045)*travel);
    }
    float cosine = saturate(dot(-direction,normal));
    float f0 = pow((u.optics.y-1)/(u.optics.y+1),2.0);
    float fresnel = f0+(1-f0)*pow(1-cosine,5.0);
    float3 glass = mix(transmission,reflected,min(0.92,fresnel));
    float3 worldNormal = rotation*normal;
    float edge = pow(1-abs(normal.z),0.7);
    glass += float3(0.70,0.88,0.80)*edge*0.075;
    // Broad softbox reflection reveals the shallow surface gradients.
    float3 halfVector = normalize(normalize(float3(-0.65,0.7,1.6))+float3(0,0,1));
    glass += float3(1,0.99,0.90)*pow(saturate(dot(worldNormal,halfVector)),180.0)*0.28;
    glass=shadeGlassCracks(glass,entry.xy,aa,cracks,uint(u.optics.w));
    float3 light=inverse*normalize(float3(-175+260*sin(u.lighting.x),65+90*cos(u.lighting.x),410));
    return float4(shadeCrackNetwork(glass,entry.xy,-direction,light,material),1);
}
