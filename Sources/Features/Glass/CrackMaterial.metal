#include <metal_stdlib>
using namespace metal;
struct MaterialSegment { float4 endpoints; float4 appearance; };
struct MaterialVertex {
    float4 position [[position]];
    float2 local;
    float4 appearance;
    float2 normal;
    float length;
};
vertex MaterialVertex crackMaterialVertex(uint vertexID [[vertex_id]], uint instance [[instance_id]],
                                          device const MaterialSegment *segments [[buffer(0)]]) {
    const float2 corners[6]={float2(0,-1),float2(1,-1),float2(0,1),float2(0,1),float2(1,-1),float2(1,1)};
    MaterialSegment s=segments[instance];
    float2 delta=s.endpoints.zw-s.endpoints.xy;
    float len=max(length(delta),0.001);
    float2 direction=delta/len,normal=float2(-direction.y,direction.x);
    float padding=1.0+max(s.appearance.x,s.appearance.y);
    float2 c=corners[vertexID],local=float2(mix(-padding,len+padding,c.x),c.y*padding);
    float2 p=s.endpoints.xy+direction*local.x+normal*local.y;
    MaterialVertex out;
    // Texture row zero corresponds to glass y=0, shared by every render path.
    out.position=float4(p.x/210*2-1,1-p.y/360*2,0,1);
    out.local=local; out.appearance=s.appearance; out.normal=normal; out.length=len;
    return out;
}
fragment float4 crackMaterialFragment(MaterialVertex in [[stage_in]]) {
    float along=clamp(in.local.x/in.length,0.0,1.0);
    float width=mix(in.appearance.x,in.appearance.y,along);
    float distance=length(float2(in.local.x-clamp(in.local.x,0.0,in.length),in.local.y));
    float coverage=1-smoothstep(width*0.30,width*0.5+0.30,distance);
    float offset=width*0.5+0.20;
    float glint=1-smoothstep(width*0.2,width*0.5+0.28,
                           length(float2(in.local.x-clamp(in.local.x,0.0,in.length),in.local.y-offset)));
    float variation=0.6+0.4*sin(in.local.x*2.3+in.appearance.z*31)*sin(in.local.x*0.71+in.appearance.w*17);
    glint *= variation;
    float angle=in.appearance.w;
    float2 n=float2(in.normal.x*cos(angle)-in.normal.y*sin(angle),in.normal.x*sin(angle)+in.normal.y*cos(angle));
    return float4(n*glint,glint,coverage);
}
