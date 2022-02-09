/*****************************************************************************
 MIT License

 Copyright(c) 2022 Alexander Veselov

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this softwareand associated documentation files(the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and /or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions :

 The above copyright noticeand this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 *****************************************************************************/

#ifndef UTILS_H
#define UTILS_H

#include "../common.h"

float3 reflect(float3 v, float3 n)
{
    return -v + 2.0f * dot(v, n) * n;
}

float3 TangentToWorld(float3 dir, float3 n)
{
    float3 axis = fabs(n.x) > 0.001f ? (float3)(0.0f, 1.0f, 0.0f) : (float3)(1.0f, 0.0f, 0.0f);
    float3 t = normalize(cross(axis, n));
    float3 b = cross(n, t);

    return normalize(b * dir.x + t * dir.y + n * dir.z);
}

float Luma(float3 rgb)
{
    return dot(rgb, (float3)(0.299f, 0.587f, 0.114f));
}

unsigned int WangHash(unsigned int x)
{
    x = (x ^ 61) ^ (x >> 16);
    x = x + (x << 3);
    x = x ^ (x >> 4);
    x = x * 0x27d4eb2d;
    x = x ^ (x >> 15);
    return x;
}

float4 UnpackRGBA8(uint data)
{
    float r = (float)( data        & 0xFF);
    float g = (float)((data >>  8) & 0xFF);
    float b = (float)((data >> 16) & 0xFF);
    float a = (float)((data >> 24) & 0xFF);

    return (float4)(r, g, b, a) / 255.0f;
}

float3 UnpackRGBTex(uint data, uint* texture_idx)
{
    float r = (float)(data & 0xFF);
    float g = (float)((data >> 8) & 0xFF);
    float b = (float)((data >> 16) & 0xFF);
    *texture_idx =   ((data >> 24) & 0xFF);

    return (float3)(r, g, b) / 255.0f;
}

float3 UnpackRGBE(uint rgbe)
{
    int r = (int)(rgbe >> 0 ) & 0xFF;
    int g = (int)(rgbe >> 8 ) & 0xFF;
    int b = (int)(rgbe >> 16) & 0xFF;
    int e = (int)(rgbe >> 24);

    float f = ldexp(1.0f, e - (128 + 8));
    return (float3)(r, g, b) * f;
}

void UnpackRoughnessMetalness(uint data, float* roughness, uint* roughness_idx,
    float* metalness, uint* metalness_idx)
{
    *roughness = (float)((data >> 0 ) & 0xFF) / 255.0f;
    *roughness_idx =    ((data >> 8 ) & 0xFF);
    *metalness = (float)((data >> 16) & 0xFF) / 255.0f;
    *metalness_idx =    ((data >> 24) & 0xFF);
}

void UnpackIorEmissionIdxTransparency(uint data, float* ior, uint* emission_idx,
    float* transparency, uint* transparency_idx)
{
    *ior = (float)((data >> 0) & 0xFF) / 25.5f;
    *emission_idx = ((data >> 8) & 0xFF);
    *transparency = (float)((data >> 16) & 0xFF) / 255.0f;
    *transparency_idx = ((data >> 24) & 0xFF);
}

#endif // UTILS_H
