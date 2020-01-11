#include <metal_stdlib>
using namespace metal;

#import "Config.h"


#define TERRAIN_SCALE 2
#define TERRAIN_HEIGHT 0.5

struct FunctionOutIn {
    float4 position[[position]];
    float4 color[[flat]];
};

#pragma mark Compute Kernels

kernel void tessellation_kernel(device MTLQuadTessellationFactorsHalf *factors[[buffer(0)]],device uint32_t *indices[[buffer(1)]], uint2 tid[[thread_position_in_grid]]) {
  
    const uint patchID = tid.y*TERRAIN_PATCHES_X+tid.x;
    indices[patchID] = patchID;
    
    uint factor = 8;
    
    factors[patchID].edgeTessellationFactor[0] = factor;
    factors[patchID].edgeTessellationFactor[1] = factor;
    factors[patchID].edgeTessellationFactor[2] = factor;
    factors[patchID].edgeTessellationFactor[3] = factor;
    factors[patchID].insideTessellationFactor[0] = factor;
    factors[patchID].insideTessellationFactor[1] = factor;
}

#pragma mark Post-Tessellation Vertex Functions

[[patch(quad,4)]] vertex FunctionOutIn tessellation_vertex(uint pid[[patch_id]],float2 uv[[position_in_patch]],constant float4x4 &viewProjectionMatrix[[buffer(0)]],texture2d<float> map[[texture(0)]]) {
  
    float aspect = (float)H/(float)W; 
        
    uint patchY = pid/TERRAIN_PATCHES_X;
    uint patchX = pid%TERRAIN_PATCHES_X;
    
    float2 patchUV = float2(patchX,patchY)/float2(TERRAIN_PATCHES_X,TERRAIN_PATCHES_Y);
    
    float4 position = float4(
        patchUV.x+uv.x/TERRAIN_PATCHES_X,
        patchUV.y+uv.y/TERRAIN_PATCHES_Y,
        0,
        1
    );
    
    constexpr sampler sam(min_filter::linear, mag_filter::linear, mip_filter::none, address::mirrored_repeat);
        
    position.z = (map.sample(sam,float2(position.xy)).r);
    
    float4 worldPosition = float4(
        (position.x-0.5f)*TERRAIN_SCALE,
        (position.y-0.5f)*aspect*TERRAIN_SCALE,
        (position.z-0.5f)*TERRAIN_HEIGHT,
        1
    );
        
    FunctionOutIn vertexOut;
    vertexOut.position = viewProjectionMatrix*worldPosition;
    vertexOut.color = float4(1.0,1.0,1.0,1.0);
    
    return vertexOut;
}

#pragma mark Fragment Function

fragment float4 tessellation_fragment(FunctionOutIn fragmentIn[[stage_in]]) {
    return fragmentIn.color;
}
