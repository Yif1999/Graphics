#ifndef SHADOW_SAMPLING_PCSS_INCLUDED
#define SHADOW_SAMPLING_PCSS_INCLUDED

#define N_SAMPLE 16
static float2 poissonDisk[16] = {
    float2( -0.94201624, -0.39906216 ),
    float2( 0.94558609, -0.76890725 ),
    float2( -0.094184101, -0.92938870 ),
    float2( 0.34495938, 0.29387760 ),
    float2( -0.91588581, 0.45771432 ),
    float2( -0.81544232, -0.87912464 ),
    float2( -0.38277543, 0.27676845 ),
    float2( 0.97484398, 0.75648379 ),
    float2( 0.44323325, -0.97511554 ),
    float2( 0.53742981, -0.47373420 ),
    float2( -0.26496911, -0.41893023 ),
    float2( 0.79197514, 0.19090188 ),
    float2( -0.24188840, 0.99706507 ),
    float2( -0.81409955, 0.91437590 ),
    float2( 0.19984126, 0.78641367 ),
    float2( 0.14383161, -0.14100790 )
};

TEXTURE2D(_MyShadowmapTexture);
SAMPLER(sampler_MyShadowmapTexture);

float2 RotateVec2(float2 v, float angle)
{
    float s = sin(angle);
    float c = cos(angle);

    return float2(v.x*c+v.y*s, -v.x*s+v.y*c);
}

float2 ComputeAverageBlockerData(float4 shadowCoord, float rotateAngle, float searchSize, float shadowmapSize, float orthRadius)
{
    float d_average = 0.0;
    float count = 0.0001;

    float3 lightDir = normalize(_MainLightPosition.xyz);
    float lightTan = lightDir.y / sqrt(1 - lightDir.y * lightDir.y + 0.0001);
    float texelSize = orthRadius*4/shadowmapSize;
    float bias = searchSize * texelSize / lightTan / orthRadius / 2.0;
        
    for(int i=0; i<N_SAMPLE; i++)
    {
        float2 offset = RotateVec2(poissonDisk[i], rotateAngle) * searchSize;
        float2 uv = shadowCoord.xy + offset / shadowmapSize;

        float d_sample = SAMPLE_TEXTURE2D(_MyShadowmapTexture, sampler_MyShadowmapTexture, uv).z;
        if (d_sample > shadowCoord.z + bias)
        {
            count += 1;
            d_average += d_sample;
        }
    }

    return float2(d_average / count, count);
}

float SampleShadowPCF(TEXTURE2D_SHADOW_PARAM(ShadowMap, sampler_ShadowMap), float4 shadowCoord, float kernelSize, float rotateAngle, float shadowmapSize, float orthRadius, float orthRadius0)
{
    float attenuation = 0.0f;

    float3 lightDir = normalize(_MainLightPosition.xyz);
    float lightTan = lightDir.y / sqrt(1 - lightDir.y * lightDir.y + 0.0001);
    float texelSize = orthRadius*4/shadowmapSize;
    float bias = (kernelSize - 2.0 * orthRadius0/orthRadius) * texelSize / lightTan / orthRadius / 2.0;

    for (int i=0; i<N_SAMPLE; i++)
    {
        float2 offset = RotateVec2(poissonDisk[i], rotateAngle)*kernelSize;
        float2 uv = shadowCoord.xy + offset / shadowmapSize;

        if (!SAMPLE_TEXTURE2D_SHADOW(ShadowMap, sampler_ShadowMap, float3(uv, shadowCoord.z+bias)))
            attenuation += 1.0f;
    }
    return 1.0 - attenuation / N_SAMPLE;
}

float RandomRange(float2 p, float min, float max)
{
    float random = frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453123);
    random = random * (max - min);
    random = random + min;
    return random;
}
#endif
