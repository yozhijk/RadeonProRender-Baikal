#ifndef BXDF_UBERV2_BRICKS
#define BXDF_UBERV2_BRICKS
// Diffuse layer
float3 UberV2_Lambert_Evaluate(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    return shader_data->diffuse_color.xyz / PI;
}

float UberV2_Lambert_GetPdf(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    return fabs(wo.y) / PI;
}

/// Lambert BRDF sampling
float3 UberV2_Lambert_Sample(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    const float3 kd = UberV2_Lambert_Evaluate(shader_data, wi, *wo, TEXTURE_ARGS);

    *wo = Sample_MapToHemisphere(sample, make_float3(0.f, 1.f, 0.f), 1.f);

    *pdf = fabs((*wo).y) / PI;

    return kd;
}

// Reflection/Coating
/*
Microfacet GGX
*/
// Distribution fucntion
float UberV2_MicrofacetDistribution_GGX_D(float roughness, float3 m)
{
    float ndotm = fabs(m.y);
    float ndotm2 = ndotm * ndotm;
    float sinmn = native_sqrt(1.f - clamp(ndotm * ndotm, 0.f, 1.f));
    float tanmn = ndotm > DENOM_EPS ? sinmn / ndotm : 0.f;
    float a2 = roughness * roughness;
    float denom = (PI * ndotm2 * ndotm2 * (a2 + tanmn * tanmn) * (a2 + tanmn * tanmn));
    return denom > DENOM_EPS ? (a2 / denom) : 1.f;
}

// PDF of the given direction
float UberV2_MicrofacetDistribution_GGX_GetPdf(
    // Halfway vector
    float3 m,
    // Rougness
    float roughness,
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    float mpdf = UberV2_MicrofacetDistribution_GGX_D(roughness, m) * fabs(m.y);
    // See Humphreys and Pharr for derivation
    float denom = (4.f * fabs(dot(wo, m)));

    return denom > DENOM_EPS ? mpdf / denom : 0.f;
}

// Sample the distribution
void UberV2_MicrofacetDistribution_GGX_SampleNormal(
    // Roughness
    float roughness,
    // Differential geometry
    UberV2ShaderData const* shader_data,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wh
)
{
    float r1 = sample.x;
    float r2 = sample.y;

    // Sample halfway vector first, then reflect wi around that
    float theta = atan2(roughness * native_sqrt(r1), native_sqrt(1.f - r1));
    float costheta = native_cos(theta);
    float sintheta = native_sin(theta);

    // phi = 2*PI*ksi2
    float phi = 2.f * PI * r2;
    float cosphi = native_cos(phi);
    float sinphi = native_sin(phi);

    // Calculate wh
    *wh = make_float3(sintheta * cosphi, costheta, sintheta * sinphi);
}

//
float UberV2_MicrofacetDistribution_GGX_G1(float roughness, float3 v, float3 m)
{
    float ndotv = fabs(v.y);
    float mdotv = fabs(dot(m, v));

    float sinnv = native_sqrt(1.f - clamp(ndotv * ndotv, 0.f, 1.f));
    float tannv = ndotv > DENOM_EPS ? sinnv / ndotv : 0.f;
    float a2 = roughness * roughness;
    return 2.f / (1.f + native_sqrt(1.f + a2 * tannv * tannv));
}

// Shadowing function also depends on microfacet distribution
float UberV2_MicrofacetDistribution_GGX_G(float roughness, float3 wi, float3 wo, float3 wh)
{
    return UberV2_MicrofacetDistribution_GGX_G1(roughness, wi, wh) * UberV2_MicrofacetDistribution_GGX_G1(roughness, wo, wh);
}

float3 UberV2_MicrofacetGGX_Evaluate(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST,
    float3 ks
)
{
    // Incident and reflected zenith angles
    float costhetao = fabs(wo.y);
    float costhetai = fabs(wi.y);

    // Calc halfway vector
    float3 wh = normalize(wi + wo);

    float denom = (4.f * costhetao * costhetai);

    return denom > DENOM_EPS ? ks * UberV2_MicrofacetDistribution_GGX_G(shader_data->reflection_roughness, wi, wo, wh) * UberV2_MicrofacetDistribution_GGX_D(shader_data->reflection_roughness, wh) / denom : 0.f;
}


float UberV2_MicrofacetGGX_GetPdf(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    float3 wh = normalize(wo + wi);

    return UberV2_MicrofacetDistribution_GGX_GetPdf(wh, shader_data->reflection_roughness, shader_data, wi, wo, TEXTURE_ARGS);
}

float3 UberV2_MicrofacetGGX_Sample(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf,
    float3 ks
)
{
    float3 wh;
    UberV2_MicrofacetDistribution_GGX_SampleNormal(shader_data->reflection_roughness, shader_data, TEXTURE_ARGS, sample, &wh);

    *wo = -wi + 2.f*fabs(dot(wi, wh)) * wh;

    *pdf = UberV2_MicrofacetDistribution_GGX_GetPdf(wh, shader_data->reflection_roughness, shader_data, wi, *wo, TEXTURE_ARGS);

    return UberV2_MicrofacetGGX_Evaluate(shader_data, wi, *wo, TEXTURE_ARGS, ks);
}

/*
Ideal reflection BRDF
*/
float3 UberV2_IdealReflect_Evaluate(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    return 0.f;
}

float UberV2_IdealReflect_GetPdf(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    return 0.f;
}

float3 UberV2_IdealReflect_Sample(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf,
    float3 ks)
{
    // Mirror reflect wi
    *wo = normalize(make_float3(-wi.x, wi.y, -wi.z));

    // PDF is infinite at that point, but deltas are going to cancel out while evaluating
    // so set it to 1.f
    *pdf = 1.f;

    float coswo = fabs((*wo).y);

    // Return reflectance value
    return coswo > DENOM_EPS ? (ks * (1.f / coswo)) : 0.f;
}

// Refraction
/*
Ideal refraction BTDF
*/

float3 UberV2_IdealRefract_Evaluate(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    return 0.f;
}

float UberV2_IdealRefract_GetPdf(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    return 0.f;
}

float3 UberV2_IdealRefract_Sample(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    const float3 ks = shader_data->refraction_color.xyz;

    float etai = 1.f;
    float etat = shader_data->refraction_ior;
    float cosi = wi.y;

    bool entering = cosi > 0.f;

    // Revert normal and eta if needed
    if (!entering)
    {
        float tmp = etai;
        etai = etat;
        etat = tmp;
    }

    float eta = etai / etat;
    float sini2 = 1.f - cosi * cosi;
    float sint2 = eta * eta * sini2;

    if (sint2 >= 1.f)
    {
        *pdf = 0.f;
        return 0.f;
    }

    float cost = native_sqrt(max(0.f, 1.f - sint2));

    // Transmitted ray
    *wo = normalize(make_float3(eta * -wi.x, entering ? -cost : cost, eta * -wi.z));

    *pdf = 1.f;

    return cost > DENOM_EPS ? (eta * eta * ks / cost) : 0.f;
}


float3 UberV2_MicrofacetRefractionGGX_Evaluate(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    const float3 ks = shader_data->refraction_color.xyz;
    const float roughness = max(shader_data->refraction_roughness, ROUGHNESS_EPS);

    float ndotwi = wi.y;
    float ndotwo = wo.y;

    if (ndotwi * ndotwo >= 0.f)
    {
        return 0.f;
    }

    float etai = 1.f;
    float etat = shader_data->refraction_ior;

    // Revert normal and eta if needed
    if (ndotwi < 0.f)
    {
        float tmp = etai;
        etai = etat;
        etat = tmp;
    }

    // Calc halfway vector
    float3 ht = -(etai * wi + etat * wo);
    float3 wh = normalize(ht);

    float widotwh = fabs(dot(wh, wi));
    float wodotwh = fabs(dot(wh, wo));

    float denom = dot(ht, ht);
    denom *= (fabs(ndotwi) * fabs(ndotwo));

    return denom > DENOM_EPS ? (ks * (widotwh * wodotwh)  * (etat)* (etat)*
        UberV2_MicrofacetDistribution_GGX_G(roughness, wi, wo, wh) * UberV2_MicrofacetDistribution_GGX_D(roughness, wh) / denom) : 0.f;
}

float UberV2_MicrofacetRefractionGGX_GetPdf(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    const float roughness = max(shader_data->refraction_roughness, ROUGHNESS_EPS);

    float ndotwi = wi.y;
    float ndotwo = wo.y;

    if (ndotwi * ndotwo >= 0.f)
    {
        return 0.f;
    }

    float etai = 1.f;
    float etat = shader_data->refraction_ior;

    // Revert normal and eta if needed
    if (ndotwi < 0.f)
    {
        float tmp = etai;
        etai = etat;
        etat = tmp;
    }

    // Calc halfway vector
    float3 ht = -(etai * wi + etat * wo);

    float3 wh = normalize(ht);

    float wodotwh = fabs(dot(wo, wh));

    float whpdf = UberV2_MicrofacetDistribution_GGX_D(roughness, wh) * fabs(wh.y);

    float whwo = wodotwh * etat * etat;

    float denom = dot(ht, ht);

    return denom > DENOM_EPS ? whpdf * whwo / denom : 0.f;
}

float3 UberV2_MicrofacetRefractionGGX_Sample(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    const float3 ks = shader_data->refraction_color.xyz;
    const float roughness = max(shader_data->refraction_roughness, ROUGHNESS_EPS);

    float ndotwi = wi.y;

    if (ndotwi == 0.f)
    {
        *pdf = 0.f;
        return 0.f;
    }

    float etai = 1.f;
    float etat = shader_data->refraction_ior;
    float s = 1.f;

    // Revert normal and eta if needed
    if (ndotwi < 0.f)
    {
        float tmp = etai;
        etai = etat;
        etat = tmp;
        s = -s;
    }

    float3 wh;
    UberV2_MicrofacetDistribution_GGX_SampleNormal(roughness, shader_data, TEXTURE_ARGS, sample, &wh);

    float c = dot(wi, wh);
    float eta = etai / etat;

    float d = 1 + eta * (c * c - 1);

    if (d <= 0.f)
    {
        *pdf = 0.f;
        return 0.f;
    }

    *wo = normalize((eta * c - s * native_sqrt(d)) * wh - eta * wi);

    *pdf = UberV2_MicrofacetRefractionGGX_GetPdf(shader_data, wi, *wo, TEXTURE_ARGS);

    return UberV2_MicrofacetRefractionGGX_Evaluate(shader_data, wi, *wo, TEXTURE_ARGS);
}

float3 UberV2_Passthrough_Sample(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    *wo = -wi;
    float coswo = fabs((*wo).y);

    // PDF is infinite at that point, but deltas are going to cancel out while evaluating
    // so set it to 1.f
    *pdf = 1.f;

    return coswo > 1e-5f ? (1.f / coswo) : 0.f;
}

float3 UberV2_Reflection_Evaluate(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    const bool is_singular = (shader_data->reflection_roughness < ROUGHNESS_EPS);
    const float metalness = shader_data->reflection_metalness;

    const float3 ks = shader_data->reflection_color.xyz;

    float3 color = mix((float3)(1.0f, 1.0f, 1.0f), ks, metalness);

    return is_singular ?
        UberV2_IdealReflect_Evaluate(shader_data, wi, wo, TEXTURE_ARGS) :
        UberV2_MicrofacetGGX_Evaluate(shader_data, wi, wo, TEXTURE_ARGS, color);
}

float3 UberV2_Refraction_Evaluate(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    const bool is_singular = shader_data->refraction_roughness;

    return is_singular ?
        UberV2_IdealRefract_Evaluate(shader_data, wi, wo, TEXTURE_ARGS) :
        UberV2_MicrofacetRefractionGGX_Evaluate(shader_data, wi, wo, TEXTURE_ARGS);
}

float UberV2_Reflection_GetPdf(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    const bool is_singular = (shader_data->reflection_roughness < ROUGHNESS_EPS);

    return is_singular ?
        UberV2_IdealReflect_GetPdf(shader_data, wi, wo, TEXTURE_ARGS) :
        UberV2_MicrofacetGGX_GetPdf(shader_data, wi, wo, TEXTURE_ARGS);
}

float UberV2_Refraction_GetPdf(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    const bool is_singular = (shader_data->refraction_roughness < ROUGHNESS_EPS);

    return is_singular ?
        UberV2_IdealRefract_GetPdf(shader_data, wi, wo, TEXTURE_ARGS) :
        UberV2_MicrofacetRefractionGGX_GetPdf(shader_data, wi, wo, TEXTURE_ARGS);
}

float3 UberV2_Reflection_Sample(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    const float3 ks = shader_data->reflection_color.xyz;
    const bool is_singular = (shader_data->reflection_roughness < ROUGHNESS_EPS);
    const float metalness = shader_data->reflection_metalness;

    float3 color = mix((float3)(1.0f, 1.0f, 1.0f), ks, metalness);

    return is_singular ?
        UberV2_IdealReflect_Sample(shader_data, wi, TEXTURE_ARGS, wo, pdf, color) :
        UberV2_MicrofacetGGX_Sample(shader_data, wi, TEXTURE_ARGS, sample, wo, pdf, color);
}

float3 UberV2_Refraction_Sample(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    const bool is_singular = (shader_data->refraction_roughness < ROUGHNESS_EPS);

    return is_singular ?
        UberV2_IdealRefract_Sample(shader_data, wi, TEXTURE_ARGS, sample, wo, pdf) :
        UberV2_MicrofacetRefractionGGX_Sample(shader_data, wi, TEXTURE_ARGS, sample, wo, pdf);
}

float3 UberV2_Coating_Sample(
    // Preprocessed shader input data
    UberV2ShaderData const* shader_data,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    const float3 ks = shader_data->coating_color.xyz;

    return UberV2_IdealReflect_Sample(shader_data, wi, TEXTURE_ARGS, wo, pdf, ks);
}

#endif
