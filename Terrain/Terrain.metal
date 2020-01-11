#include <metal_stdlib>
using namespace metal;

#import "Config.h"


#pragma mark Structs


// Vertex-to-Fragment struct
struct FunctionOutIn {
    float4 position[[position]];
    half4 color[[flat]];
};

#pragma mark Compute Kernels

// Quad compute kernel
kernel void tessellation_kernel_quad(device MTLQuadTessellationFactorsHalf *factors[[buffer(0)]],device uint32_t *indices[[buffer(1)]], uint2 tid[[thread_position_in_grid]]) {
  
    // Simple passthrough operation
    // More sophisticated compute kernels might determine the tessellation factors based on the state of the scene (e.g. camera distance)
    
    
    const uint patchID = tid.y*TERRAIN_PATCHES_X+tid.x;
    indices[patchID] = patchID;
    
    uint edge_factor = 16;
    uint inside_factor = 16;
    
    factors[patchID].edgeTessellationFactor[0] = edge_factor;
    factors[patchID].edgeTessellationFactor[1] = edge_factor;
    factors[patchID].edgeTessellationFactor[2] = edge_factor;
    factors[patchID].edgeTessellationFactor[3] = edge_factor;
    factors[patchID].insideTessellationFactor[0] = inside_factor;
    factors[patchID].insideTessellationFactor[1] = inside_factor;
}

#pragma mark Post-Tessellation Vertex Functions

// Quad post-tessellation vertex function
[[patch(quad,4)]] vertex FunctionOutIn tessellation_vertex(uint pid[[patch_id]], float2 uv[[position_in_patch]]) {
  
    float aspect = 1.0; 
        
    uint patchY = pid/TERRAIN_PATCHES_X;
    uint patchX = pid%TERRAIN_PATCHES_X;
    
    float2 patchUV = float2(patchX,patchY)/float2(TERRAIN_PATCHES_X,TERRAIN_PATCHES_Y);
    
    float4 position = float4(
        patchUV.x+uv.x/TERRAIN_PATCHES_X,
        patchUV.y+uv.y/TERRAIN_PATCHES_Y,
        0,
        1
    );
    
    float4 worldPosition = float4(
        (position.x-0.5f)*TERRAIN_SCALE,
        (position.y-0.5f*aspect)*TERRAIN_SCALE,
        0,//(position.z-0.5f),
        1
    );
        
    
    // Output
    FunctionOutIn vertexOut;
    vertexOut.position = worldPosition;
    vertexOut.color = half4(1.0,1.0,1.0,1.0);
    
    return vertexOut;
}

#pragma mark Fragment Function

// Common fragment function
fragment half4 tessellation_fragment(FunctionOutIn fragmentIn[[stage_in]]) {
    return fragmentIn.color;
}
