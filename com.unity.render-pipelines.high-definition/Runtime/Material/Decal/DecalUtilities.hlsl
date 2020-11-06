#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Decal/Decal.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Decal/DecalPrepassBuffer.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Decal/DecalLightLoopDef.hlsl"

DECLARE_DBUFFER_TEXTURE(_DBufferTexture);

// In order that the lod for with transpartent decal better match the lod for opaque decal
// We use ComputeTextureLOD with bias == 0.5
void EvalDecalMask( PositionInputs posInput, float3 vtxNormal, float3 positionRWSDdx, float3 positionRWSDdy, DecalData decalData,
                    inout float4 DBuffer0, inout float4 DBuffer1, inout float4 DBuffer2, inout float2 DBuffer3, inout float alpha)
{
    // Get the relative world camera to decal matrix
    float4x4 worldToDecal = ApplyCameraTranslationToInverseMatrix(decalData.worldToDecal);
    float3 positionDS = mul(worldToDecal, float4(posInput.positionWS, 1.0)).xyz;
    positionDS = positionDS * float3(1.0, -1.0, 1.0) + float3(0.5, 0.5, 0.5);  // decal clip space
    if ((all(positionDS.xyz > 0.0) && all(1.0 - positionDS.xyz > 0.0)))
    {
        float2 uvScale = float2(decalData.normalToWorld[3][0], decalData.normalToWorld[3][1]);
        float2 uvBias = float2(decalData.normalToWorld[3][2], decalData.normalToWorld[3][3]);
        positionDS.xz = positionDS.xz * uvScale + uvBias;
        positionDS.xz = frac(positionDS.xz);

        // clamp by half a texel to avoid sampling neighboring textures in the atlas
        float2 clampAmount = float2(0.5 / _DecalAtlasResolution.x, 0.5 / _DecalAtlasResolution.y);

        // need to compute the mipmap LOD manually because we are sampling inside a loop
        float3 positionDSDdx = mul(worldToDecal, float4(positionRWSDdx, 0.0)).xyz; // transform the derivatives to decal space, any translation is irrelevant
        float3 positionDSDdy = mul(worldToDecal, float4(positionRWSDdy, 0.0)).xyz;

        // Following code match the code in DecalData.hlsl used for DBuffer. It have the same kind of condition and similar code structure
        uint affectFlags = (int)(decalData.blendParams.z + 0.5f); // 1 albedo, 2 normal, 4 metal, 8 AO, 16 smoothness
        float fadeFactor = decalData.normalToWorld[0][3];
        // Check if this decal projector require angle fading
        float2 angleFade = float2(decalData.normalToWorld[1][3], decalData.normalToWorld[2][3]);

        // Angle fade is disabled if decal layers isn't enabled for consistency with DBuffer Decal
        // The test against _EnableDecalLayers is done here to refresh realtime as AngleFade is cached data and need a decal refresh to be updated.
        if (angleFade.x > 0.0f && _EnableDecalLayers) // if angle fade is enabled
        {
            float dotAngle = 1.0 - dot(vtxNormal, decalData.normalToWorld[2].xyz);
            // See equation in DecalSystem.cs - simplified to a madd here
            float angleFadeFactor = 1.0 - saturate(dotAngle * angleFade.x + angleFade.y);
            fadeFactor *= angleFadeFactor;
        }

        float albedoMapBlend = fadeFactor;
        float maskMapBlend = fadeFactor;

        // Albedo
        // We must always sample diffuse texture due to opacity that can affect everything)
        {
            float4 src = decalData.baseColor;

            // We use scaleBias value to now if we have init a texture. 0 mean a texture is bound
            bool diffuseTextureBound = (decalData.diffuseScaleBias.x > 0) && (decalData.diffuseScaleBias.y > 0);
            if (diffuseTextureBound)
            {
                // Caution: We can't compute LOD inside a dynamic loop. The gradient are not accessible.
                float2 diffuseMin = decalData.diffuseScaleBias.zw + clampAmount;                                    // offset into atlas is in .zw
                float2 diffuseMax = decalData.diffuseScaleBias.zw + decalData.diffuseScaleBias.xy - clampAmount;    // scale relative to full atlas size is in .xy so total texture extent in atlas is (1,1) * scale

                float2 sampleDiffuse = clamp(positionDS.xz * decalData.diffuseScaleBias.xy + decalData.diffuseScaleBias.zw, diffuseMin, diffuseMax);
                float2 sampleDiffuseDdx = positionDSDdx.xz * decalData.diffuseScaleBias.xy; // factor in the atlas scale
                float2 sampleDiffuseDdy = positionDSDdy.xz * decalData.diffuseScaleBias.xy;
                float  lodDiffuse = ComputeTextureLOD(sampleDiffuseDdx, sampleDiffuseDdy, _DecalAtlasResolution, 0.5);
               
                src *= SAMPLE_TEXTURE2D_LOD(_DecalAtlas2D, _trilinear_clamp_sampler_DecalAtlas2D, sampleDiffuse, lodDiffuse);
            }

            src.w *= fadeFactor;
            albedoMapBlend = src.w;  // diffuse texture alpha affects all other channels

            // Accumulate in dbuffer (mimic what ROP are doing)
            DBuffer0.xyz = (affectFlags & 1) ? src.xyz * src.w + DBuffer0.xyz * (1.0 - src.w) : DBuffer0.xyz; // Albedo
            DBuffer0.w = (affectFlags & 1) ? DBuffer0.w * (1.0 - src.w) : DBuffer0.w; // Albedo alpha

            // Specific to transparent and requested by the artist: use decal alpha if it is higher than transparent alpha
            alpha = max(alpha, albedoMapBlend);
        }

        // Metal/ao/smoothness - 28 -> 1C
        #ifdef DECALS_4RT
        if (affectFlags & 0x1C)
        #else // only smoothness in 3RT mode
        if (affectFlags & 0x10)
        #endif
        {
            float4 src;

            // We use scaleBias value to now if we have init a texture. 0 mean a texture is bound
            bool maskTextureBound = (decalData.maskScaleBias.x > 0) && (decalData.maskScaleBias.y > 0);
            if (maskTextureBound)
            {
                // Caution: We can't compute LOD inside a dynamic loop. The gradient are not accessible.
                float2 maskMin = decalData.maskScaleBias.zw + clampAmount;
                float2 maskMax = decalData.maskScaleBias.zw + decalData.maskScaleBias.xy - clampAmount;

                float2 sampleMask = clamp(positionDS.xz * decalData.maskScaleBias.xy + decalData.maskScaleBias.zw, maskMin, maskMax);

                float2 sampleMaskDdx = positionDSDdx.xz * decalData.maskScaleBias.xy;
                float2 sampleMaskDdy = positionDSDdy.xz * decalData.maskScaleBias.xy;
                float  lodMask = ComputeTextureLOD(sampleMaskDdx, sampleMaskDdy, _DecalAtlasResolution, 0.5);

                src = SAMPLE_TEXTURE2D_LOD(_DecalAtlas2D, _trilinear_clamp_sampler_DecalAtlas2D, sampleMask, lodMask);
                src.z *= decalData.scalingMBAndAngle.y; // Blue channel (opacity)
                maskMapBlend *= src.z; // store before overwriting with smoothness
                #ifdef DECALS_4RT
                src.x *= decalData.scalingMBAndAngle.x; // Metal
                src.y = lerp(decalData.remappingAOS.x, decalData.remappingAOS.y, src.y); // Remap AO
                #endif
                src.z = lerp(decalData.remappingAOS.z, decalData.remappingAOS.w, src.w); // Remap Smoothness
            }
            else
            {
                src.z = decalData.scalingMBAndAngle.y; // Blue channel (opacity)
                maskMapBlend *= src.z; // store before overwriting with smoothness
                #ifdef DECALS_4RT
                src.x = decalData.scalingMBAndAngle.x; // Metal
                src.y = decalData.remappingAOS.x; // AO
                #endif
                src.z = decalData.remappingAOS.z; // Smoothness
            }

            src.w = (decalData.blendParams.y == 1.0) ? maskMapBlend : albedoMapBlend;

            // Accumulate in dbuffer (mimic what ROP are doing)
            #ifdef DECALS_4RT
            DBuffer2.x = (affectFlags & 4) ? src.x * src.w + DBuffer2.x * (1.0 - src.w) : DBuffer2.x; // Metal
            DBuffer3.x = (affectFlags & 4) ? DBuffer3.x * (1.0 - src.w) : DBuffer3.x; // Metal alpha

            DBuffer2.y = (affectFlags & 8) ? src.y * src.w + DBuffer2.y * (1.0 - src.w) : DBuffer2.y; // AO
            DBuffer3.y = (affectFlags & 8) ? DBuffer3.y * (1.0 - src.w) : DBuffer3.y; // AO alpha
            #endif
            DBuffer2.z = (affectFlags & 16) ? src.z * src.w + DBuffer2.z * (1.0 - src.w) : DBuffer2.z; // Smoothness
            DBuffer2.w = (affectFlags & 16) ? DBuffer2.w * (1.0 - src.w) : DBuffer2.w; // Smoothness alpha
        }

        // Normal
        if (affectFlags & 2)
        {
            float3 normalTS;

            // We use scaleBias value to now if we have init a texture. 0 mean a texture is bound
            bool normalTextureBound = (decalData.normalScaleBias.x > 0) && (decalData.normalScaleBias.y > 0);
            if (normalTextureBound)
            {
                // Caution: We can't compute LOD inside a dynamic loop. The gradient are not accessible.
                float2 normalMin = decalData.normalScaleBias.zw + clampAmount;
                float2 normalMax = decalData.normalScaleBias.zw + decalData.normalScaleBias.xy - clampAmount;
                float2 sampleNormal = clamp(positionDS.xz * decalData.normalScaleBias.xy + decalData.normalScaleBias.zw, normalMin, normalMax);
                float2 sampleNormalDdx = positionDSDdx.xz * decalData.normalScaleBias.xy;
                float2 sampleNormalDdy = positionDSDdy.xz * decalData.normalScaleBias.xy;
                float  lodNormal = ComputeTextureLOD(sampleNormalDdx, sampleNormalDdy, _DecalAtlasResolution, 0.5);
                normalTS = UnpackNormalmapRGorAG(SAMPLE_TEXTURE2D_LOD(_DecalAtlas2D, _trilinear_clamp_sampler_DecalAtlas2D, sampleNormal, lodNormal));
            }
            else
            {
                normalTS = float3(0.0, 0.0, 1.0);
            }

            float4 src;
            src.xyz = mul((float3x3)decalData.normalToWorld, normalTS) * 0.5 + 0.5; // The " * 0.5 + 0.5" mimic what is happening when calling EncodeIntoDBuffer()
            src.w = (decalData.blendParams.x == 1.0) ? maskMapBlend : albedoMapBlend;

            // Accumulate in dbuffer (mimic what ROP are doing)
            DBuffer1.xyz = src.xyz * src.w + DBuffer1.xyz * (1.0 - src.w);
            DBuffer1.w = DBuffer1.w * (1.0 - src.w);
        }
    }
}

#if !defined(_SURFACE_TYPE_TRANSPARENT) || !defined(HAS_LIGHTLOOP)

    void Foo( PositionInputs posInput, float3 vtxNormal, float3 positionRWSDdx, float3 positionRWSDdy, DecalData decalData,
                        inout float4 DBuffer0, inout float4 DBuffer1, inout float4 DBuffer2, inout float2 DBuffer3, inout float alpha)
    {
        float4x4 worldToDecal = ApplyCameraTranslationToInverseMatrix(decalData.worldToDecal);
        float3 positionDS = mul(worldToDecal, float4(posInput.positionWS, 1.0)).xyz;
        positionDS = positionDS * float3(1.0, -1.0, 1.0) + float3(0.5, 0.5, 0.5);  // decal clip space
        if ((all(positionDS.xyz > 0.0) && all(1.0 - positionDS.xyz > 0.0)))
        {
            DBuffer0.xyzw += float4(1.0, 0.0, 0.0, 1.0);
        }
    }

    uint xGenerateLogBaseBufferIndex(uint2 tileIndex, uint numTilesX, uint numTilesY, uint eyeIndex)
    {
        uint eyeOffset = eyeIndex * numTilesX * numTilesY;
        return (eyeOffset + (tileIndex.y * numTilesX) + tileIndex.x);
    }

    float xLogBase(float x, float b)
    {
        return log2(x) / log2(b);
    }

    int xSnapToClusterIdxFlex(float z_in, float suggestedBase, bool logBasePerTile)
    {
    #if USE_LEFT_HAND_CAMERA_SPACE
        float z = z_in;
    #else
        float z = -z_in;
    #endif

        const int C = 1 << g_iLog2NumClusters;
        const float rangeFittedDistance = max(0, z - g_fNearPlane) / (g_fFarPlane - g_fNearPlane);
        return (int)clamp( xLogBase( lerp(1.0, PositivePow(suggestedBase, (float) C), rangeFittedDistance), suggestedBase), 0.0, (float)(C - 1));
    }

    uint xGetLightClusterIndex(uint2 tileIndex, float linearDepth)
    {
        float logBase = g_fClustBase;
        if (g_isLogBaseBufferEnabled)
        {
            const uint logBaseIndex = xGenerateLogBaseBufferIndex(tileIndex, _NumTileClusteredX, _NumTileClusteredY, unity_StereoEyeIndex);
            logBase = g_logBaseBuffer[logBaseIndex];
        }

        return xSnapToClusterIdxFlex(linearDepth, logBase, g_isLogBaseBufferEnabled != 0);
    }

    uint xGenerateLayeredOffsetBufferIndex(uint lightCategory, uint2 tileIndex, uint clusterIndex, uint numTilesX, uint numTilesY, int numClusters, uint eyeIndex)
    {
        #define LIGHTCATEGORY_COUNT (6)
        // Each eye is split into category, cluster, x, y

        uint eyeOffset = eyeIndex * LIGHTCATEGORY_COUNT * numClusters * numTilesX * numTilesY;
        int lightOffset = ((lightCategory * numClusters + clusterIndex) * numTilesY + tileIndex.y) * numTilesX + tileIndex.x;

        return (eyeOffset + lightOffset);
    }

    void xGetCountAndStart(PositionInputs posInput, uint lightCategory, out uint start, out uint lightCount)
    {
        uint2 tileIndex    = posInput.tileCoord;
        uint  clusterIndex = xGetLightClusterIndex(tileIndex, posInput.linearDepth);

        int nrClusters = (1 << g_iLog2NumClusters);

        const int idx = xGenerateLayeredOffsetBufferIndex(lightCategory, tileIndex, clusterIndex, _NumTileClusteredX, _NumTileClusteredY, nrClusters, unity_StereoEyeIndex);

        uint dataPair = g_vLayeredOffsetsBuffer[idx];
        start = dataPair & 0x7ffffff;
        lightCount = (dataPair >> 27) & 31;
    }

    uint xFetchIndex(uint lightStart, uint lightOffset)
    {
        return g_vLightListGlobal[lightStart + lightOffset];
    }

    DecalData xFetchDecal(uint index)
    {
        return _DecalDatas[index];
    }
#endif

#if defined(_SURFACE_TYPE_TRANSPARENT) && defined(HAS_LIGHTLOOP) // forward transparent using clustered decals
DecalData FetchDecal(uint start, uint i)
{
#ifndef LIGHTLOOP_DISABLE_TILE_AND_CLUSTER
    int j = FetchIndex(start, i);
#else
    int j = start + i;
#endif
    return _DecalDatas[j];
}

DecalData FetchDecal(uint index)
{
    return _DecalDatas[index];
}
#endif

DecalSurfaceData GetDecalSurfaceData(PositionInputs posInput, float3 vtxNormal, inout float alpha)
{
#if defined(_SURFACE_TYPE_TRANSPARENT) && defined(HAS_LIGHTLOOP)  // forward transparent using clustered decals
    uint decalCount, decalStart;
    DBufferType0 DBuffer0 = float4(0.0, 0.0, 0.0, 1.0);
    DBufferType1 DBuffer1 = float4(0.5, 0.5, 0.5, 1.0);
    DBufferType2 DBuffer2 = float4(0.0, 0.0, 0.0, 1.0);
#ifdef DECALS_4RT
    DBufferType3 DBuffer3 = float2(1.0, 1.0);
#else
    float2 DBuffer3 = float2(1.0, 1.0);
#endif

#ifndef LIGHTLOOP_DISABLE_TILE_AND_CLUSTER
    GetCountAndStart(posInput, LIGHTCATEGORY_DECAL, decalStart, decalCount);

    // Fast path is when we all pixels in a wave are accessing same tile or cluster.
    uint decalStartLane0;
    bool fastPath = IsFastPath(decalStart, decalStartLane0);

#else // LIGHTLOOP_DISABLE_TILE_AND_CLUSTER
    decalCount = _DecalCount;
    decalStart = 0;
#endif

    float3 positionRWS = posInput.positionWS;

    // get world space ddx/ddy for adjacent pixels to be used later in mipmap lod calculation
    float3 positionRWSDdx = ddx(positionRWS);
    float3 positionRWSDdy = ddy(positionRWS);

    uint decalLayerMask = GetMeshRenderingDecalLayer();

    // Scalarized loop. All decals that are in a tile/cluster touched by any pixel in the wave are loaded (scalar load), only the ones relevant to current thread/pixel are processed.
    // For clarity, the following code will follow the convention: variables starting with s_ are wave uniform (meant for scalar register),
    // v_ are variables that might have different value for each thread in the wave (meant for vector registers).
    // This will perform more loads than it is supposed to, however, the benefits should offset the downside, especially given that decal data accessed should be largely coherent
    // Note that the above is valid only if wave intriniscs are supported.
    uint v_decalListOffset = 0;
    uint v_decalIdx = decalStart;
    while (v_decalListOffset < decalCount)
    {
#ifndef LIGHTLOOP_DISABLE_TILE_AND_CLUSTER
        v_decalIdx = FetchIndex(decalStart, v_decalListOffset);
#else
        v_decalIdx = decalStart + v_decalListOffset;
#endif // LIGHTLOOP_DISABLE_TILE_AND_CLUSTER

        uint s_decalIdx = ScalarizeElementIndex(v_decalIdx, fastPath);
        if (s_decalIdx == -1)
            break;

        DecalData s_decalData = FetchDecal(s_decalIdx);
        bool isRejected = (s_decalData.decalLayerMask & decalLayerMask) == 0;

        // If current scalar and vector decal index match, we process the decal. The v_decalListOffset for current thread is increased.
        // Note that the following should really be ==, however, since helper lanes are not considered by WaveActiveMin, such helper lanes could
        // end up with a unique v_decalIdx value that is smaller than s_decalIdx hence being stuck in a loop. All the active lanes will not have this problem.
        if (s_decalIdx >= v_decalIdx)
        {
            v_decalListOffset++;
            if (!isRejected)
                EvalDecalMask(posInput, vtxNormal, positionRWSDdx, positionRWSDdy, s_decalData, DBuffer0, DBuffer1, DBuffer2, DBuffer3, alpha);
        }

    }
#else // Opaque - used DBuffer

    DBufferType0 DBuffer0 = float4(0.0, 0.0, 0.0, 1.0);
    DBufferType1 DBuffer1 = float4(0.5, 0.5, 0.5, 1.0);
    DBufferType2 DBuffer2 = float4(0.0, 0.0, 0.0, 1.0);
#ifdef DECALS_4RT
    DBufferType3 DBuffer3 = float2(1.0, 1.0);
#else
    float2 DBuffer3 = float2(1.0, 1.0);
#endif

if (g_prepasslessDecals != 0) {
    #if !defined(TILE_SIZE_CLUSTERED)
    #define TILE_SIZE_CLUSTERED (32)
    #endif
    posInput.tileCoord = uint2(posInput.positionSS.xy) / TILE_SIZE_CLUSTERED;

    #define LIGHTCATEGORY_DECAL (4)
    uint decalCount, decalStart;
    /* TODO: Get clustering working. It doesn't work right now. Nothing happens unless we're inside a decal's volume, in which
       case we will see that decal's influence with some flickering. */
// if Clustering
        // xGetCountAndStart(posInput, LIGHTCATEGORY_DECAL, decalStart, decalCount);
        // uint decalStartLane0;
        // bool fastPath = IsFastPath(decalStart, decalStartLane0);
    // ---
        DecalMaterialPassGetCountAndStart(posInput, LIGHTCATEGORY_DECAL, decalStart, decalCount);
        // #if SCALARIZE_LIGHT_LOOP
        //     uint decalLane0;
        //     fastPath = IsFastPath(decanlStart, decalLane0);

        //     if (fastPath)
        //     {
        //         decanlStart = decalLane0;
        //     }
        // #endif
// else
    // decalCount = _DecalCount;
    // decalStart = 0;
    // bool fastPath = false;
// endif
    float3 positionRWS = posInput.positionWS;
    // get world space ddx/ddy for adjacent pixels to be used later in mipmap lod calculation
    float3 positionRWSDdx = ddx(positionRWS);
    float3 positionRWSDdy = ddy(positionRWS);
    uint decalLayerMask = GetMeshRenderingDecalLayer();
    uint v_decalListOffset = 0;
    uint v_decalIdx = decalStart;
// #if true
    while (v_decalListOffset < decalCount)
    {
// if Clustering
            // v_decalIdx = xFetchIndex(decalStart, v_decalListOffset);
        // ---
            v_decalIdx = DecalMaterialPassFetchIndex(decalStart, v_decalListOffset);
            // #if SCALARIZE_LIGHT_LOOP
            //     uint s_decalIdx = ScalarizeElementIndex(v_decalIdx, fastPath);
            // #else
                uint s_decalIdx = v_decalIdx;
            // #endif
// else
        // v_decalIdx = decalStart + v_decalListOffset;
        // uint s_decalIdx = v_decalIdx;
// endif

        if (s_decalIdx == -1) break;

        DecalData s_decalData = _DecalDatas[s_decalIdx];
        bool isRejected = (s_decalData.decalLayerMask & decalLayerMask) == 0;
        // if (s_decalIdx >= v_decalIdx)
        {
            v_decalListOffset++;
            if (!isRejected)
                // Foo(posInput, vtxNormal, positionRWSDdx, positionRWSDdy, s_decalData, DBuffer0, DBuffer1, DBuffer2, DBuffer3, alpha);
                EvalDecalMask(posInput, vtxNormal, positionRWSDdx, positionRWSDdy, s_decalData, DBuffer0, DBuffer1, DBuffer2, DBuffer3, alpha);
        }
    }
// #else // #if true
//     if (decalCount > 0) {
//         uint idx = g_vDecalLightListGlobal[decalStart + v_decalListOffset];
//         // FIXME: This should show different colors, one for each of the three active decals.
//         // However, it only shows green, meaning that idx is always 0. Needs investigation.
//         if (idx == 0) {
//             DBuffer0 = float4(0.0, 1.0, 0.0, 1.0);
//         } else if (idx == 1) {
//             DBuffer0 = float4(0.0, 0.0, 1.0, 1.0);
//         } else if (idx == 2) {
//             DBuffer0 = float4(1.0, 0.0, 1.0, 1.0);
//         } else if (idx == 3) {
//             DBuffer0 = float4(0.0, 1.0, 1.0, 1.0);
//         } else if (idx > 3) {
//             DBuffer0 = float4(1.0, 0.0, 0.0, 1.0);
//         }
//     }
// #endif // #if true

} else { // (g_PrepasslessDecals)
    DBuffer0 = LOAD_TEXTURE2D_X(_DBufferTexture0, int2(posInput.positionSS.xy));
    DBuffer1 = LOAD_TEXTURE2D_X(_DBufferTexture1, int2(posInput.positionSS.xy));
    DBuffer2 = LOAD_TEXTURE2D_X(_DBufferTexture2, int2(posInput.positionSS.xy));
#ifdef DECALS_4RT
    DBuffer3 = LOAD_TEXTURE2D_X(_DBufferTexture3, int2(posInput.positionSS.xy)).xy;
#endif
} // (g_PrepasslessDecals)

#endif

    DecalSurfaceData decalSurfaceData;
    DECODE_FROM_DBUFFER(DBuffer, decalSurfaceData);

    return decalSurfaceData;
}
