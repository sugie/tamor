#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
struct JewelVertex { float4 position; float4 normal; };
struct JewelInstance { float4x4 model; float4 color; float4 material; };
struct JewelFrame { float4 values; float4 dimensions; float4 scene; };
struct JewelOut { float4 position [[position]]; float3 normal; float3 world; float3 local; float3 localView;float3 localNormal;float3 axisX;float3 axisY;float3 axisZ; float scale; uint objectID [[flat]]; float4 color; float4 material; };
vertex JewelOut jewelVertex(uint v [[vertex_id]], uint i [[instance_id]],constant JewelVertex* vertices [[buffer(0)]],constant JewelInstance* instances [[buffer(1)]],constant JewelFrame& frame [[buffer(2)]]) {
    JewelVertex a=vertices[v];JewelInstance b=instances[i];float4 p=b.model*a.position;
    JewelOut o;o.position=float4(p.x,p.y,0.5-p.z*0.20,1);
    o.axisX=normalize(b.model[0].xyz);o.axisY=normalize(b.model[1].xyz);o.axisZ=normalize(b.model[2].xyz);
    o.scale=length(b.model[0].xyz);o.objectID=i+1;
    o.localView=float3(o.axisX.z,o.axisY.z,o.axisZ.z);o.localNormal=a.normal.xyz;
    o.normal=normalize((b.model*float4(a.normal.xyz,0)).xyz);o.world=p.xyz;o.local=a.position.xyz;o.color=b.color;o.material=b.material;return o;
}
// Approximate visible-spectrum material constants; mm-scale attenuation, independent of camera zoom.
struct GemOptics {float ior;float roughness;float3 absorption;float dispersion;};
GemOptics optics(int kind) {
    if(kind==4)return {1.765,0.055,float3(0.32,0.12,0.008),0.009};
    if(kind==5)return {1.50,0.075,float3(2.8,2.6,2.3),0.002};
    if(kind==1)return {1.54,0.12,float3(2.8,2.65,2.5),0.001};
    if(kind==2)return {1.585,0.065,float3(0.27,0.014,0.14),0.006};
    if(kind==3)return {1.765,0.055,float3(0.012,0.36,0.18),0.009};
    return {2.417,0.028,float3(0.003,0.002,0.001),0.044};
}
float3 studio(float3 d) {
    d=normalize(d);
    float3 c=mix(float3(0.007,0.014,0.028),float3(0.22,0.29,0.36),smoothstep(-0.8,0.9,d.y));
    float key=pow(max(0.0,dot(d,normalize(float3(-0.65,0.75,1.1)))),48.0);
    float strip=pow(max(0.0,dot(d,normalize(float3(0.85,0.1,0.65)))),100.0);
    float rim=pow(max(0.0,dot(d,normalize(float3(0.15,-0.6,-0.8)))),34.0);
    return c+key*float3(5.0,4.7,4.1)+strip*float3(2.2,2.8,3.6)+rim*float3(2.5,1.9,1.15);
}
// Shared physical window: background, transmitted rays and reflected illumination.
// Coordinates are in the ring's world space; slot rotation never moves the window.
float windowPanes(float2 p,float aa) {
    float2 q=float2(dot(p,float2(0.94,0.342)),dot(p,float2(-0.342,0.94)))+float2(0.09,0.04);
    float2 spacing=float2(0.32,0.44);
    float2 bars=abs(fract(q/spacing+0.5)-0.5)*spacing;
    float pane=smoothstep(0.013-aa,0.013+aa,min(bars.x,bars.y));
    float frame=1-smoothstep(0.035,0.06,max(abs(q.x)-2.2,abs(q.y)-1.9));
    return pane*frame;
}
float3 windowRoom(float2 p,constant JewelFrame& frame) {
    float aa=max(0.002,2.5/max(frame.dimensions.x,1.0));
    float panes=windowPanes(p,aa);
    float t=frame.scene.y; // A separate clock freezes in low power / Reduce Motion / static mode.
    float beam=exp(-pow((p.x*0.7+p.y*0.3-0.35*sin(t*0.16))*1.8,2.0));
    float falloff=0.62+0.38*exp(-dot(p-float2(-0.35,0.45),p-float2(-0.35,0.45))*0.45);
    float3 wall=float3(0.055,0.082,0.12);
    float3 c=wall+float3(0.24,0.29,0.34)*panes*falloff*(0.65+0.35*beam);
    float warm=exp(-dot((p-float2(0.62,0.58))*float2(7,9),(p-float2(0.62,0.58))*float2(7,9)));
    c+=float3(0.22,0.12,0.035)*warm;
    // Quiet the backdrop continuously as atoms replace the gem, without changing scenes.
    float lattice=smoothstep(1.5,2.6,frame.values.z)*frame.values.y;
    return mix(c,float3(0.055,0.085,0.12),lattice*0.9);
}
float3 gemLighting(float3 direction,float3 origin,constant JewelFrame& frame) {
    if(frame.scene.x>0.5)return studio(direction);
    float3 d=normalize(direction);
    float plane=d.z>=0 ? 1.8:-1.2;
    float distance=abs(plane-origin.z)/max(0.25,abs(d.z));
    float2 p=origin.xy+d.xy*distance;
    float facing=smoothstep(0.05,0.5,d.z);
    // The front-facing studio window uses the same mullions; onyx reflects it without transmission.
    return studio(d)*0.4+windowRoom(p,frame)*(0.45+1.7*facing);
}
float3 tone(float3 c) {return clamp((c*(2.51*c+0.03))/(c*(2.43*c+0.59)+0.14),0.0,1.0);}
float4 shadeGem(JewelOut in,constant JewelFrame& frame,float pathMM,float3 inside) {
    float noise=fract(sin(dot(floor(in.position.xy),float2(12.9898,78.233)))*43758.5453);
    if(in.material.z<=0 || noise>in.material.z) discard_fragment();
    if(in.material.x<0.5 && in.material.w>0 && (in.local.x+1.0)*0.5<in.material.w) discard_fragment();
    float3 n=normalize(in.normal),v=float3(0,0,1),l=normalize(float3(-0.7,0.85,1.6));
    float diffuse=max(0.0,dot(n,l));float3 c=in.color.rgb;
    if(in.material.x<0.5) {
        GemOptics m=optics(int(in.material.y));
        if(frame.dimensions.w>=12288)m.roughness*=0.65;
        float nv=max(0.001,abs(dot(n,v))),f0=pow((m.ior-1)/(m.ior+1),2.0);
        float fresnel=f0+(1-f0)*pow(1-nv,5.0);
        float3 reflection=gemLighting(reflect(-v,n),in.world,frame);
        float a=m.roughness*m.roughness,nh=max(0.0,dot(n,normalize(l+v)));
        float distribution=a*a/(M_PI_F*pow(nh*nh*(a*a-1)+1,2.0)+0.00001);
        float3 trans=exp(-m.absorption*pathMM);
        c=reflection*fresnel+(1-fresnel)*inside*trans;
        c+=min(3.0,distribution*0.018)*float3(1,0.96,0.90);
        if(int(in.material.y)==1)c=reflection*fresnel+float3(0.007,0.009,0.012)*(0.4+diffuse);
        float3 spectrum=0.5+0.5*cos(float3(0,2.1,4.2)+dot(reflect(-v,n),float3(15,11,7)));
        c+=spectrum*m.dispersion*min(2.0,length(reflection))*fresnel;
    } else {
        float spec=pow(max(0.0,dot(n,normalize(l+v))),64.0);
        c=c*(0.22+0.70*diffuse)+float3(0.95,0.90,0.76)*spec*0.6;
    }
    return float4(tone(max(c,float3(0))),1);
}
float3 ringBackdrop(float2 p,constant JewelFrame& frame);
float3 boardBackdrop(float2 p,constant JewelFrame& frame);
float3 linearColor(float3 c) {return select(pow((c+0.055)/1.055,float3(2.4)),c/12.92,c<=0.04045);}
float3 transmittedScene(float3 exitPoint,float3 direction,constant JewelFrame& frame) {
    if(direction.z>=-0.05 || frame.scene.x>1.5)return gemLighting(direction,exitPoint,frame);
    float distance=max(0.0,exitPoint.z+1.2)/max(0.15,-direction.z);
    float2 point=exitPoint.xy+direction.xy*distance;
    // Ring background and transmission share linear radiance, then the same tone mapping.
    if(frame.scene.x<0.5)return ringBackdrop(point,frame);
    return linearColor(boardBackdrop(point,frame))+studio(direction)*0.12;
}
fragment float4 jewelBackFragment(JewelOut in [[stage_in]]) {
    if(in.normal.z>=-0.0001 || in.material.z<0.001)discard_fragment();
    // The normal magnitude identifies the object, preventing refraction into another gem's map.
    return float4(normalize(in.normal)*float(in.objectID),in.position.z);
}
fragment float4 jewelFragment(JewelOut in [[stage_in]],constant JewelFrame& frame [[buffer(0)]],texture2d<float> backs [[texture(0)]]) {
    if(in.material.x>=0.5 || int(in.material.y)==1)return shadeGem(in,frame,0,float3(0));
    GemOptics m=optics(int(in.material.y));
    float3 direction=refract(float3(0,0,-1),normalize(in.normal),1.0/m.ior);
    constexpr sampler sampleMap(coord::normalized,address::clamp_to_edge,filter::nearest);
    float2 uv=in.position.xy/frame.dimensions.xy;
    float4 back=backs.sample(sampleMap,uv);
    float depth=(0.5-back.w)/0.2;
    float distance=max(0.0,in.world.z-depth)/max(0.15,-direction.z);
    // One bounded correction along the refracted ray; the object ID rejects silhouette leakage.
    float2 offset=direction.xy*distance*float2(0.5,-0.5);
    float4 shifted=backs.sample(sampleMap,uv+offset);
    if(abs(length(shifted.xyz)-float(in.objectID))<0.35 && shifted.w>in.position.z)back=shifted;
    if(abs(length(back.xyz)-float(in.objectID))>=0.35 || back.w<=in.position.z)
        return shadeGem(in,frame,2.0,gemLighting(direction,in.world,frame)*0.35);
    depth=(0.5-back.w)/0.2;
    distance=max(0.0,in.world.z-depth)/max(0.15,-direction.z);
    float pathMM=clamp(distance/max(0.001,in.scale)*5.0,0.02,25.0);
    float3 normal=normalize(back.xyz),exitDirection=refract(direction,-normal,m.ior);
    float3 reflected=reflect(direction,normal);
    float f0=pow((m.ior-1)/(m.ior+1),2.0);
    float exitF=f0+(1-f0)*pow(1-abs(dot(direction,normal)),5.0);
    bool tir=length_squared(exitDirection)<0.0001;
    float3 inside=tir ? gemLighting(reflected,in.world+direction*distance,frame)*0.78 :
        transmittedScene(in.world+direction*distance,exitDirection,frame)*(1-exitF)+gemLighting(reflected,in.world+direction*distance,frame)*exitF;
    return shadeGem(in,frame,pathMM*(tir ? 1.4:1.0),inside);
}
fragment float4 jewelRayFragment(JewelOut in [[stage_in]],constant JewelFrame& frame [[buffer(0)]],
    raytracing::primitive_acceleration_structure structure [[buffer(1)]],constant JewelVertex* vertices [[buffer(2)]]) {
    using namespace raytracing;
    GemOptics m=optics(int(in.material.y));
    float3 direction=refract(-normalize(in.localView),normalize(in.localNormal),1.0/m.ior);
    float3 origin=in.local+direction*0.002;float distanceMM=0;float3 inside=float3(0.01);
    intersector<triangle_data> query;
    query.assume_geometry_type(geometry_type::triangle);
    for(int bounce=0;bounce<4;bounce++) {
        ray r(origin,direction,0.001,8.0);
        auto hit=query.intersect(r,structure);
        if(hit.type==intersection_type::none)break;
        distanceMM+=hit.distance*5.0;
        uint index=hit.primitive_id*3;
        float3 normal=normalize(vertices[index].normal.xyz);
        float3 exitDirection=refract(direction,-normal,m.ior);
        origin+=direction*hit.distance;
        if(length_squared(exitDirection)>0.0001) {
            float3 world=in.axisX*exitDirection.x+in.axisY*exitDirection.y+in.axisZ*exitDirection.z;
            float3 exitPoint=in.world+(in.axisX*(origin.x-in.local.x)+in.axisY*(origin.y-in.local.y)+in.axisZ*(origin.z-in.local.z))*in.scale;
            inside=transmittedScene(exitPoint,world,frame);break;
        }
        direction=reflect(direction,normal);origin+=direction*0.002;
    }
    return shadeGem(in,frame,max(0.01,distanceMM),inside);
}
struct JewelBG { float4 position [[position]];float2 uv; };
vertex JewelBG jewelBackgroundVertex(uint id [[vertex_id]]) {
    float2 p=float2(id==1 ? 3:-1,id==2 ? 3:-1);JewelBG o;o.position=float4(p,0.99,1);o.uv=p;return o;
}
float3 ringBackdrop(float2 p,constant JewelFrame& frame) {
    float r=length(p),aa=3.0/max(frame.dimensions.x,1.0);
    float3 c=windowRoom(p,frame);
    // Darken the rim into the surrounding app chrome, keeping all twelve seats illuminated.
    float vignette=smoothstep(0.91,1.19,r);
    c=mix(c,float3(0.00194,0.00333,0.00521),vignette);
    if(frame.values.y<0.999) {
        float orbit=(1-frame.values.y)*(1-smoothstep(0.001,0.001+aa,abs(r-0.66)))*0.22;
        float outer=(1-frame.values.y)*(1-smoothstep(0.0005,0.0005+aa,abs(r-0.89)))*0.07;
        float inner=(1-frame.values.y)*(1-smoothstep(0.0005,0.0005+aa,abs(r-0.43)))*0.055;
        c=mix(c,float3(0.09,0.055,0.019),clamp((orbit+outer+inner)*2.5,0.0,1.0));
        for(int slot=0;slot<12;slot++) {
            float t=slot*2*M_PI_F/12+frame.values.w;
            float2 q=p-float2(sin(t),-cos(t))*0.66;
            bool active=slot%3==0;
            float seat=1-smoothstep(0.0015,0.0015+aa,abs(length(q)-0.108));
            float outerSeat=1-smoothstep(0.001,0.001+aa,abs(length(q)-0.123));
            int packed=int(frame.dimensions.w),style=packed/4096;
            bool earned=(packed & (1<<slot))!=0;
            if(earned && style>0) {
                float leaves=pow(max(0.0,cos(atan2(q.y,q.x)*16)),4.0);
                float wreath=(1-smoothstep(0.004,0.015,abs(length(q)-0.145)))*leaves;
                c+=float3(0.8,0.64,0.36)*wreath*0.6*(1-frame.values.y);
                if(style==2)c+=float3(0.34,0.26,0.09)*exp(-pow((length(q)-0.135)*32,2))*0.2*(1-frame.values.y);
            }
            float strength=active ? 0.42:0.075;
            c=mix(c,float3(0.09,0.055,0.019),clamp((seat+outerSeat*0.25)*strength*(1-frame.values.y)*1.8,0.0,1.0));
        }
        float a=atan2(p.y,p.x),tick=pow(max(0.0,cos(a*60.0)),90.0);
        c+=float3(0.58,0.50,0.36)*tick*smoothstep(0.86,0.87,r)*(1-smoothstep(0.888,0.9,r))*0.30;
        float mark=exp(-dot((p-float2(0,-0.9))*float2(150,120),(p-float2(0,-0.9))*float2(150,120)));
        c+=float3(0.90,0.73,0.42)*mark;
    } else {
        c+=float3(0.035,0.048,0.06)*exp(-r*r*2.2);
        float grid=pow(max(0.0,cos(p.x*32))*max(0.0,cos(p.y*32)),80.0)*0.028;
        c+=grid*smoothstep(1.6,2.2,frame.values.z);
    }
    return c;
}
float3 boardBackdrop(float2 p,constant JewelFrame& frame) {
    float2 uv=(p+1)/2;
    float2 cell=(uv-0.05)/0.9*frame.values.y;
    float2 edge=min(fract(cell),1-fract(cell));
    float line=1-smoothstep(0.004,0.018,min(edge.x,edge.y));
    float check=fmod(floor(cell.x)+floor(cell.y),2.0);
    float3 c=mix(float3(0.045,0.067,0.084),float3(0.075,0.096,0.107),check);
    c+=line*float3(0.045,0.046,0.04);
    if(any(uv<0.05)||any(uv>0.95))c=float3(0.025,0.043,0.063);
    return c;
}

fragment float4 jewelBackgroundFragment(JewelBG in [[stage_in]],constant JewelFrame& frame [[buffer(0)]]) {
    return float4(tone(ringBackdrop(in.uv,frame)),1);
}
fragment float4 miniBoardBackground(JewelBG in [[stage_in]],constant JewelFrame& frame [[buffer(0)]]) {
    return float4(linearColor(boardBackdrop(in.uv,frame)),1);
}
fragment float4 soulTargetFragment(JewelOut in [[stage_in]],constant JewelFrame& frame [[buffer(0)]]) {
    float2 p=in.local.xy;float r=length(p);
    float halo=exp(-r*r*5.5)*0.27;
    float orb=(1-smoothstep(0.37,0.61,r))*0.66;
    float highlight=exp(-dot(p-float2(-0.12,0.16),p-float2(-0.12,0.16))*110.0)*0.9;
    float angle=fract(atan2(p.x,p.y)/(2*M_PI_F)+1.0);
    float ring=(1-smoothstep(0.013,0.035,abs(r-0.64)))*step(angle,in.material.w)*0.75;
    float alpha=min(0.94,halo+orb+ring+highlight*0.35)*(1-smoothstep(0.88,1.0,r));
    float3 c=mix(in.color.rgb,float3(1,0.85,0.79),highlight*0.8)+in.color.rgb*ring*0.5;
    return float4(c*alpha,alpha); // Premultiplied throughout shader, blend state and transparent MTKView.
}
