/**********************************************************************
 Copyright (c) 2016 Advanced Micro Devices, Inc. All rights reserved.
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 ********************************************************************/
#extension GL_EXT_gpu_shader4 : enable
#define PI 3.14159265358979323846

varying vec3 WorldPos;
varying vec3 Normal;
varying vec2 Uv;

uniform vec3 CameraPosition;
uniform vec3 DiffuseAlbedo;
uniform vec3 GlossAlbedo;
uniform float GlossRoughness;
uniform float DiffuseRoughness;
uniform float Ior;

uniform int HasDiffuseAlbedoTexture;

uniform sampler2D DiffuseAlbedoTexture;
uniform int HasIblTexture;
uniform sampler2D IblTexture;
uniform float IblMultiplier;

uniform int HasGlossAlbedoTexture;
uniform sampler2D GlossAlbedoTexture;

float RadicalInverse(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

vec2 HammersleySample(uint i, uint N)
{
    return vec2(float(i) / float(N), RadicalInverse(i));
}

// Frostbite version from: 
float SmithGGXCorrelated(float NdotL, float NdotV, float AlphaG)
{
    float AlphaG2 = AlphaG * AlphaG;
    float LambdaGGXV = NdotL * sqrt((-NdotV * AlphaG2 + NdotV) * NdotV + AlphaG2);
    float LambdaGGXL = NdotV * sqrt((-NdotL * AlphaG2 + NdotL) * NdotL + AlphaG2);
    return 0.5 / (LambdaGGXV + LambdaGGXL);
}

float D_GGX(float NdotH, float M)
{
    float M2 = M * M;
    float F = (NdotH * M2 - NdotH) * NdotH + 1.0;
    return M2 / (F * F);
}

float F_SchlickFd90(float R0, float Fd90, float NdotV)
{
    float OneMinusNdotV = (1 - NdotV);
    float OneMinusNdotV2 = OneMinusNdotV * OneMinusNdotV;
    float OneMinusNdotV5 = OneMinusNdotV2 * OneMinusNdotV2 * OneMinusNdotV;
    return (R0 + (Fd90 - R0) * OneMinusNdotV5);
}

float F_Schlick(float Ior, float NdotV)
{
    float R0 = (1 - Ior) / (1 + Ior) * (1 - Ior) / (1 + Ior);
    float OneMinusNdotV = (1 - clamp(NdotV, 0.0, 1.0));
    float OneMinusNdotV2 = OneMinusNdotV * OneMinusNdotV;
    float OneMinusNdotV5 = OneMinusNdotV2 * OneMinusNdotV2 * OneMinusNdotV;
    return R0 + (1.0 - R0) * OneMinusNdotV5;
}

float F_Dielectric(float etai, float etat, float NdotV, float NdotL)
{
    // Parallel and perpendicular polarization
    float rparl = ((etat * NdotV) - (etai * NdotL)) / ((etat * NdotV) + (etai * NdotL));
    float rperp = ((etai * NdotV) - (etat * NdotL)) / ((etai * NdotV) + (etat * NdotL));
    return (rparl*rparl + rperp*rperp) * 0.5f;
}


float GGX_D(vec3 N, vec3 M, float Roughness)
{
    float NdotM = clamp(dot(N, M), 0.0, 1.0);
    float NdotM2 = NdotM * NdotM;
    float SinMN = sqrt(1.0 - clamp(NdotM2, 0.0, 1.0));
    float TanMN = SinMN / NdotM;
    float A = Roughness * Roughness;
    float Denom = (PI * NdotM2 * NdotM2 * (A + TanMN * TanMN) * (A + TanMN * TanMN));
    return Denom > 1e-5 ? (A / Denom) : 0.0;
}

float GGX_G1(vec3 N, vec3 V, vec3 M, float Roughness)
{
    float NdotV = clamp(dot(N, V), 0.0, 1.0);
    float MdotV = clamp(dot(M, V), 0.0, 1.0);

    float SinNV = sqrt(1.0 - NdotV);
    float TanNV = SinNV / NdotV;
    float A = Roughness * Roughness;
    return 2.0 / (1.0 + sqrt(1.f + A * TanNV * TanNV));
}

float GGX_G(vec3 N, vec3 V, vec3 L, vec3 H, float Roughness)
{
    return GGX_G1(N, V, H, Roughness) * GGX_G1(N, L, H, Roughness);
}

float BRDF_GGX_Pdf(vec3 N, vec3 V, vec3 L, float Roughness)
{
    vec3 H = normalize(L + V);
    float Mpdf = GGX_D(N, H, Roughness) * clamp(dot(N, H), 0.0, 1.0);
    float Denom = (4.0 * clamp(dot(L, H), 0.0, 1.0));
    return Denom > 1e-5? Mpdf / Denom : 0.0;
}

vec3 BRDF_GGX(vec3 N, vec3 V, vec3 L, vec3 Albedo, float Roughness)
{
    if (dot(N, L) <= 0.f)
        return vec3(0.0);

    // Disney diffuse BRDF
    vec3 H = normalize(V + L);

    float NdotL = clamp(dot(N, L), 0.0, 1.0);
    float NdotV = clamp(dot(N, V), 0.0, 1.0);

    float Denom = (4.f * NdotL * NdotV);

    return Denom > 1e-5 ? Albedo * GGX_G(N, V, L, H, Roughness) * GGX_D(N, H, Roughness) / Denom : vec3(0.0);
}

// Sample the distribution
vec3 BRDF_GGX_Sample(vec3 N, vec3 T, vec3 B, vec3 V, vec3 Albedo, float Roughness, vec2 Sample, out vec3 L, out float Pdf)
{
    float r1 = Sample.x;
    float r2 = Sample.y;

    float Temp = atan(Roughness * sqrt(r1), sqrt(1.f - r1));
    float Theta = float((Temp >= 0.0) ? Temp : (Temp + 2.0 * PI));

    float CosTheta = cos(Theta);
    float SinTheta = sin(Theta);

    // phi = 2*PI*ksi2
    float CosPhi = cos(2.f*PI*r2);
    float SinPhi = sin(2.f*PI*r2);

    // Calculate wh
    vec3 H = SinTheta * CosPhi * T + CosTheta * N + SinTheta * SinPhi * B;

    // Reflect wi around wh
    L = -V + 2.0 * clamp(dot(V, H), 0.0, 1.0) * H;

    // Calc pdf
    Pdf = BRDF_GGX_Pdf(N, V, L, Roughness);

    return BRDF_GGX(N, V, L, Albedo, Roughness);
}


vec3 BRDF_DisneyDiffuse(vec3 N, vec3 V, vec3 L, vec3 Albedo, float Roughness)
{
    if (dot(N, L) <= 0.f)
        return vec3(0.0);

    // Disney diffuse BRDF
    vec3 H = normalize(V + L);
    float HdotL = clamp(dot(H, L), 0.0, 1.0);
    float NdotH = clamp(dot(N, H), 0.0, 1.0);
    float NdotL = clamp(dot(N, L), 0.0, 1.0);
    float NdotV = clamp(dot(N, V), 0.0, 1.0);

    float Fd90 = 0.5 + 2.0 * HdotL * HdotL * Roughness;
    float OneMinusNdotL = (1 - NdotL);
    float OneMinusNdotL2 = OneMinusNdotL * OneMinusNdotL;
    float OneMinusNdotL5 = OneMinusNdotL2 * OneMinusNdotL2 * OneMinusNdotL;

    float OneMinusNdotV = (1 - NdotV);
    float OneMinusNdotV2 = OneMinusNdotV * OneMinusNdotV;
    float OneMinusNdotV5 = OneMinusNdotV2 * OneMinusNdotV2 * OneMinusNdotV;

    return (Albedo / PI) * F_SchlickFd90(1.0, Fd90, NdotL) * F_SchlickFd90(1.0, Fd90, NdotV);
}

float BRDF_DisneyDiffuse_Pdf(vec3 N, vec3 V, vec3 L, float Roughness)
{
    if (dot(N, L) <= 0.f)
        return 0.0;

    return clamp(dot(N, L) / PI, 0.0, 1.0);
}

vec3 BRDF_DisneyDiffuse_Sample(vec3 N, vec3 T, vec3 B, vec3 V, vec3 Albedo, float Roughness, vec2 Sample, out vec3 L, out float Pdf)
{
    float SinPsi = sin(2 * PI * Sample.x);
    float CosPsi = cos(2 * PI * Sample.x);
    float CosTheta = pow(1.0 - Sample.y, 0.5);
    float SinTheta = sqrt(1.f - CosTheta * CosTheta);

    // Return the result
    L = normalize(T * SinTheta * CosPsi + N * CosTheta + B * SinTheta * SinPsi);
    Pdf = BRDF_DisneyDiffuse_Pdf(N, V, L, Roughness);
    return BRDF_DisneyDiffuse(N, V, L, Albedo, Roughness);
}

vec3 BRDF(vec3 N, vec3 V, vec3 L, float Ior, vec3 DiffuseAlbedo, vec3 GlossAlbedo, float DiffuseRoughness, float GlossRoughness)
{
    float F = 1.0;
    if (Ior > 1.0)
    {
        float NdotV = clamp(dot(N, V), 0.0, 1.0);
        float NdotL = clamp(dot(N, L), 0.0, 1.0);
        F = F_Schlick(Ior, NdotV);
    }
    else
    {
        F = Ior;
    }

    return (1.0 - F) * BRDF_DisneyDiffuse(N, V, L, DiffuseAlbedo, DiffuseRoughness) + F * BRDF_GGX(N, V, L, GlossAlbedo, GlossRoughness);
}

vec4 IBL(vec3 V, float Lod)
{
    float T = atan(V.x, V.z);
    float Phi = T > 0.f ? T : (T + 2.0 * PI);
    float Theta = acos(V.y);

    vec2 UV;
    UV.x = Phi / (2 * PI);
    UV.y = Theta / PI;

    return IblMultiplier * textureLod(IblTexture, UV, 0.0);
}

vec3 Integrate_IBL(vec3 N, vec3 T, vec3 B, vec3 V, float Ior, vec3 DiffuseAlbedo, vec3 GlossAlbedo, float DiffuseRoughness, float GlossRoughness)
{
    float F = 1.0;
    if (Ior > 1.0)
    {
        float NdotV = clamp(dot(N, V), 0.0, 1.0);
        F = F_Schlick(Ior, NdotV);
    }
    else
    {
        F = Ior;
    }

    vec3 I = 0.0;
    int NumSamples = 64;
    // Accumulate samples
    for (int i = 0; i < NumSamples; ++i)
    {
        // Get quasi-random sample
        vec2 Sample = HammersleySample(i, NumSamples);
        vec3 L;
        vec3 Brdf;
        float Pdf;

        if (Sample.x > F)
        {
            // Simple diffuse sampling
            Brdf = BRDF_DisneyDiffuse_Sample(N, T, B, V, DiffuseAlbedo, DiffuseRoughness, Sample, L, Pdf);
        }
        else
        {
            // GGX sampling
            Brdf = BRDF_GGX_Sample(N, T, B, V, GlossAlbedo, GlossRoughness, Sample, L, Pdf);
        }

        // Accumulate Monte-Carlo sum
        float Lod = mix(0.0, 12.0, GlossRoughness);
        I += (Pdf > 0.0 ? (Brdf * IBL(L, Lod).xyz * clamp(dot(N, L), 0.0, 1.0) / Pdf) : vec3(0.0));
    }

    return I / NumSamples;
}

vec3 GetOrthoVector(vec3 N)
{
    vec3 P;

    if (abs(N.z) > 0.f) {
        float K = sqrt(N.y*N.y + N.z*N.z);
        P.x = 0; P.y = -N.z / K; P.z = N.y / K;
    }
    else {
        float K = sqrt(N.x*N.x + N.y*N.y);
        P.x = N.y / K; P.y = -N.x / K; P.z = 0;
    }

    return normalize(P);
}

void main()
{
    vec3 V = normalize(CameraPosition - WorldPos);
    vec3 N = Normal;
    if (dot(V, N) < 0.f)
        V = -V;

    vec3 DiffuseAlbedoTemp = DiffuseAlbedo;
    vec3 GlossAlbedoTemp = GlossAlbedo;

    if (HasDiffuseAlbedoTexture != -1)
    {
        vec2 tex = Uv;
        tex.y = 1.0 - tex.y;
        DiffuseAlbedoTemp = texture2D(DiffuseAlbedoTexture, tex);
    }

    if (HasGlossAlbedoTexture != -1)
    {
        vec2 tex = Uv;
        tex.y = 1.0 - tex.y;
        GlossAlbedoTemp = texture2D(GlossAlbedoTexture, tex);
    }


    vec3 T = GetOrthoVector(N);
    vec3 B = cross(N, T);

    vec3 R = vec3(0.0);
    if (HasIblTexture != -1)
    {
        R += Integrate_IBL(N, T, B, V, Ior, DiffuseAlbedoTemp, GlossAlbedoTemp, DiffuseRoughness, GlossRoughness);
    }

    gl_FragData[0] = pow(vec4(R, 1.0), vec4(1.0 / 2.2));
}