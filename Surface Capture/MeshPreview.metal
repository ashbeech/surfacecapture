#include <metal_stdlib>
using namespace metal;

// Vertex input structure matching our Swift vertex descriptor
struct VertexIn {
    float3 position [[attribute(0)]];
};

// Vertex output structure passing data to fragment shader
struct VertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

// Camera uniforms structure
struct CameraUniforms {
    float4x4 viewProjectionMatrix;
    float3 cameraPosition;
};

// Vertex shader
vertex VertexOut vertexShader(const VertexIn vertex_in [[stage_in]],
                            constant CameraUniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    
    // Transform position to clip space
    out.position = uniforms.viewProjectionMatrix * float4(vertex_in.position, 1.0);
    
    // Calculate distance from camera for point size
    float distance = length(vertex_in.position - uniforms.cameraPosition);
    out.pointSize = max(2.0, 8.0 / distance); // Dynamic point size based on distance
    
    // Calculate color based on height (you can modify this for different visualization)
    float heightNormalized = (vertex_in.position.y + 2.0) / 4.0; // Assuming points are roughly in -2 to 2 range
    out.color = float4(0.0, heightNormalized, 1.0 - heightNormalized, 1.0);
    
    return out;
}

// Fragment shader
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                             float2 pointCoord [[point_coord]]) {
    // Create circular points
    float distance = length(pointCoord - float2(0.5));
    if (distance > 0.5) {
        discard_fragment();
    }
    
    // Apply soft edges
    float alpha = 1.0 - smoothstep(0.45, 0.5, distance);
    return float4(in.color.rgb, alpha * in.color.a);
}
