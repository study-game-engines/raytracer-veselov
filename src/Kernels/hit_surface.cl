#include "shared_structures.h"
#include "bxdf.h"
#include "utils.h"

float SampleBlueNoise(int pixel_i, int pixel_j, int sampleIndex, int sampleDimension,
    __global int* sobol_256spp_256d, __global int* scramblingTile, __global int* rankingTile)
{
    // wrap arguments
    pixel_i = pixel_i & 127;
    pixel_j = pixel_j & 127;
    sampleIndex = sampleIndex & 255;
    sampleDimension = sampleDimension & 255;

    // xor index based on optimized ranking
    int rankedSampleIndex = sampleIndex ^ rankingTile[sampleDimension + (pixel_i + pixel_j * 128) * 8];

    // fetch value in sequence
    int value = sobol_256spp_256d[sampleDimension + rankedSampleIndex * 256];

    // If the dimension is optimized, xor sequence value based on optimized scrambling
    value = value ^ scramblingTile[(sampleDimension % 8) + (pixel_i + pixel_j * 128) * 8];

    // convert to float and return
    float v = (0.5f + value) / 256.0f;
    return v;
}

float3 SampleDiffuse(float2 s, Material material, float3 normal, float2 texcoord, float3* outgoing, float* pdf)
{
    *outgoing = SampleHemisphereCosine(normal, s);
    *pdf = dot(*outgoing, normal) * INV_PI;

    float3 albedo = (sin(texcoord.x * 64) > 0) * (sin(texcoord.y * 64) > 0) + (sin(texcoord.x * 64 + PI) > 0) * (sin(texcoord.y * 64 + PI) > 0) * 2.0f;
    return albedo * material.diffuse * INV_PI;
}

float3 SampleSpecular(float2 s, Material material, float3 normal, float3 incoming, float3* outgoing, float* pdf)
{
    float alpha = material.roughness;
    float cosTheta;
    float3 wh = SampleGGX(s, normal, alpha, &cosTheta);

    *outgoing = reflect(incoming, wh);
    if (dot(*outgoing, normal) * dot(incoming, normal) < 0.0f) return 0.0f;

    float D = DistributionGGX(cosTheta, alpha);
    *pdf = D * cosTheta / (4.0f * dot(incoming, wh));
    // Actually, _material->ior_ isn't ior value, this is f0 value for now
    return D / (4.0f * dot(*outgoing, normal) * dot(incoming, normal)) * material.specular;
}

float3 SampleBrdf(float s1, float2 s, Material material, float3 normal, float2 texcoord, float3 incoming, float3* outgoing, float* pdf)
{
    bool doSpecular = dot(material.specular, (float3)(1.0f, 1.0f, 1.0f)) > 0.0f;
    bool doDiffuse = dot(material.diffuse, (float3)(1.0f, 1.0f, 1.0f)) > 0.0f;

    if (doSpecular && !doDiffuse)
    {
        return SampleSpecular(s, material, normal, incoming, outgoing, pdf);
    }
    else if (!doSpecular && doDiffuse)
    {
        return SampleDiffuse(s, material, normal, texcoord, outgoing, pdf);
    }
    else if (doSpecular && doDiffuse)
    {
        if (s1 > 0.5f)
        {
            return SampleSpecular(s, material, normal, incoming, outgoing, pdf) * 2.0f;
        }
        else
        {
            return SampleDiffuse(s, material, normal, texcoord, outgoing, pdf) * 2.0f;
        }
    }
    else
    {
        return 0.0f;
    }
}

__kernel void KernelEntry
(
    // Input
    __global Ray* incoming_rays,
    __global uint* incoming_ray_counter,
    __global uint* incoming_pixel_indices,
    __global Hit* hits,
    __global Triangle* triangles,
    __global Material* materials,
    uint bounce,
    uint width,
    uint height,
    __global uint* sample_counter,
    // Sampler
    __global int* sobol_256spp_256d,
    __global int* scramblingTile,
    __global int* rankingTile,
    // Output
    __global float3* throughputs,
    __global Ray* outgoing_rays,
    __global uint* outgoing_ray_counter,
    __global uint* outgoing_pixel_indices,
    __global float4* result_radiance
)
{
    uint incoming_ray_idx = get_global_id(0);
    uint num_incoming_rays = incoming_ray_counter[0];

    if (incoming_ray_idx >= num_incoming_rays)
    {
        return;
    }

    Hit hit = hits[incoming_ray_idx];

    if (hit.primitive_id == INVALID_ID)
    {
        return;
    }

    Ray incoming_ray = incoming_rays[incoming_ray_idx];
    float3 incoming = -incoming_ray.direction.xyz;

    uint pixel_idx = incoming_pixel_indices[incoming_ray_idx];
    uint sample_idx = sample_counter[0];

    int x = pixel_idx % width;
    int y = pixel_idx / width;

    Triangle triangle = triangles[hit.primitive_id];

    float3 position = InterpolateAttributes(triangle.v1.position,
        triangle.v2.position, triangle.v3.position, hit.bc);

    float2 texcoord = InterpolateAttributes2(triangle.v1.texcoord.xy,
        triangle.v2.texcoord.xy, triangle.v3.texcoord.xy, hit.bc);

    float3 normal = normalize(InterpolateAttributes(triangle.v1.normal,
        triangle.v2.normal, triangle.v3.normal, hit.bc));

    Material material = materials[triangle.mtlIndex];

    // Sample bxdf
    float2 s;
    s.x = SampleBlueNoise(x, y, sample_idx, 0, sobol_256spp_256d, scramblingTile, rankingTile);
    s.y = SampleBlueNoise(x, y, sample_idx, 1, sobol_256spp_256d, scramblingTile, rankingTile);
    float s1 = SampleBlueNoise(x, y, sample_idx, 2, sobol_256spp_256d, scramblingTile, rankingTile);

    float pdf = 0.0f;
    float3 throughput = 0.0f;
    float3 outgoing;
    float3 bxdf = SampleBrdf(s1, s, material, normal, texcoord, incoming, &outgoing, &pdf);

    if (pdf > 0.0)
    {
        throughput = bxdf / pdf * max(dot(outgoing, normal), 0.0f);
    }

    throughputs[pixel_idx] *= throughput;

    bool spawn_outgoing_ray = (pdf > 0.0);

    if (spawn_outgoing_ray)
    {
        ///@TODO: reduct atomic memory traffic by using LDS
        uint outgoing_ray_idx = atomic_add(outgoing_ray_counter, 1);

        Ray outgoing_ray;
        outgoing_ray.origin.xyz = position + normal * EPS;
        outgoing_ray.origin.w = 0.0f;
        outgoing_ray.direction.xyz = outgoing;
        outgoing_ray.direction.w = MAX_RENDER_DIST;

        outgoing_rays[outgoing_ray_idx] = outgoing_ray;
        outgoing_pixel_indices[outgoing_ray_idx] = pixel_idx;
    }

}
