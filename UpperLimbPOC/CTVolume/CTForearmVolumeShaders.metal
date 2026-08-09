#include <metal_stdlib>
using namespace metal;

struct CTVertexOut {
    float4 position [[position]];
    float2 uv;
};

struct CTVolumeUniforms {
    float4x4 inverseRotation;
    float4 volumeScaleAndReveal;
    float4 viewportAndTime;
};

vertex CTVertexOut ctVolumeVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0, 1.0), float2(1.0, 1.0)
    };
    CTVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

static float2 boxIntersection(float3 origin, float3 direction) {
    float3 inverseDirection = 1.0 / direction;
    float3 first = (-0.5 - origin) * inverseDirection;
    float3 second = (0.5 - origin) * inverseDirection;
    float3 nearValues = min(first, second);
    float3 farValues = max(first, second);
    return float2(max(max(nearValues.x, nearValues.y), nearValues.z),
                  min(min(farValues.x, farValues.y), farValues.z));
}

static float smoothBand(float density, float low0, float low1, float high0, float high1) {
    return smoothstep(low0, low1, density) * (1.0 - smoothstep(high0, high1, density));
}

fragment float4 ctVolumeFragment(
    CTVertexOut in [[stage_in]],
    constant CTVolumeUniforms &uniforms [[buffer(0)]],
    texture3d<float, access::sample> volume [[texture(0)]]
) {
    constexpr sampler volumeSampler(filter::linear, address::clamp_to_edge);
    float2 screen = in.uv * 2.0 - 1.0;
    screen.x *= uniforms.viewportAndTime.x;

    float3 worldOrigin = float3(screen * 0.66, -1.45);
    float3 worldDirection = float3(0.0, 0.0, 1.0);
    float3 scale = max(uniforms.volumeScaleAndReveal.xyz, float3(0.001));
    float3 origin = (uniforms.inverseRotation * float4(worldOrigin, 1.0)).xyz / scale;
    float3 direction = normalize((uniforms.inverseRotation * float4(worldDirection, 0.0)).xyz / scale);

    float2 interval = boxIntersection(origin, direction);
    float entry = max(interval.x, 0.0);
    if (interval.y <= entry) { return float4(0.0); }

    constexpr int stepCount = 176;
    float stepLength = (interval.y - entry) / float(stepCount);
    float reveal = saturate(uniforms.volumeScaleAndReveal.w);
    float3 accumulatedColor = float3(0.0);
    float accumulatedOpacity = 0.0;
    float3 voxel = 1.0 / float3(volume.get_width(), volume.get_height(), volume.get_depth());

    for (int index = 0; index < stepCount && accumulatedOpacity < 0.985; ++index) {
        float distance = entry + (float(index) + 0.5) * stepLength;
        float3 texturePoint = origin + direction * distance + 0.5;
        float density = volume.sample(volumeSampler, texturePoint).r;

        float soft = smoothBand(density, 0.34, 0.48, 0.58, 0.72);
        float bone = smoothstep(0.58, 0.76, density);
        float softOpacity = soft * 0.16 * pow(1.0 - reveal, 1.35);
        float boneOpacity = bone * 0.42 * reveal;
        float sampleOpacity = max(softOpacity, boneOpacity);
        if (sampleOpacity < 0.001) { continue; }

        float3 gradient = float3(
            volume.sample(volumeSampler, texturePoint + float3(voxel.x, 0, 0)).r
                - volume.sample(volumeSampler, texturePoint - float3(voxel.x, 0, 0)).r,
            volume.sample(volumeSampler, texturePoint + float3(0, voxel.y, 0)).r
                - volume.sample(volumeSampler, texturePoint - float3(0, voxel.y, 0)).r,
            volume.sample(volumeSampler, texturePoint + float3(0, 0, voxel.z)).r
                - volume.sample(volumeSampler, texturePoint - float3(0, 0, voxel.z)).r
        );
        float gradientLength = length(gradient);
        float lighting = gradientLength > 0.0001
            ? 0.50 + 0.50 * abs(dot(normalize(gradient), normalize(float3(0.45, -0.35, -0.82))))
            : 0.72;

        float3 surfaceColor = mix(float3(0.88, 0.56, 0.43), float3(0.62, 0.13, 0.10),
                                  smoothstep(0.42, 0.58, density));
        float3 boneColor = float3(1.0, 0.94, 0.72);
        float boneMix = saturate(boneOpacity / max(sampleOpacity, 0.0001));
        float3 sampleColor = mix(surfaceColor, boneColor, boneMix) * lighting;

        float contribution = (1.0 - accumulatedOpacity) * sampleOpacity;
        accumulatedColor += sampleColor * contribution;
        accumulatedOpacity += contribution;
    }
    return float4(accumulatedColor, accumulatedOpacity);
}
