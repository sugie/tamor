#ifndef GLASS_CRACK_SHADING_H
#define GLASS_CRACK_SHADING_H
#include <metal_stdlib>
using namespace metal;

// A surface marking for the first straight-crack object; not a fractured solid or air gap.
static float3 shadeGlassCracks(float3 color,float2 point,float aa,
                              device const float4 *segments,uint count) {
    float dark=0,light=0;
    for(uint i=0;i<count;++i) {
        float2 a=segments[i].xy,b=segments[i].zw,ab=b-a;
        float squared=dot(ab,ab);
        if(squared<1e-10) continue;
        float along=clamp(dot(point-a,ab)/squared,0.0,1.0);
        float2 nearest=a+along*ab;
        float distance=length(point-nearest);
        dark=max(dark,1-smoothstep(0.14,0.14+aa,distance));
        float2 normal=float2(-ab.y,ab.x)*rsqrt(squared);
        float highlight=length(point-nearest-normal*0.42);
        light=max(light,1-smoothstep(0.10,0.10+aa,highlight));
    }
    color=mix(color,float3(0.018,0.035,0.030),dark*0.92);
    return color+float3(0.78,0.91,0.86)*light*(1-dark)*0.65;
}
// Surface material only: no new fracture volume is inserted into ray geometry.
static float3 shadeCrackNetwork(float3 color,float2 point,float3 viewDirection,float3 lightDirection,
                                texture2d<float> material) {
    constexpr sampler sampleMaterial(coord::normalized,address::clamp_to_zero,filter::linear);
    float4 m=material.sample(sampleMaterial,(point+float2(105,180))/float2(210,360));
    float coverage=saturate(m.w), brightness=saturate(m.z);
    float2 n2=m.xy/max(m.z,0.0001);
    float3 normal=normalize(float3(n2*0.8,0.6));
    float3 halfDirection=normalize(viewDirection+lightDirection);
    float reflection=pow(saturate(abs(dot(normal,halfDirection))),18.0);
    float grazing=pow(1-saturate(abs(dot(normal,viewDirection))),3.0);
    color=mix(color,float3(0.012,0.022,0.018),coverage*0.64);
    return color+float3(0.87,0.95,0.94)*brightness*(0.52+reflection*1.8+grazing*0.5);
}
#endif
