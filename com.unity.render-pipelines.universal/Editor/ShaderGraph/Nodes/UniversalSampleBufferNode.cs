using System.Collections.Generic;
using System;
using UnityEngine;
using UnityEditor.Graphing;
using UnityEditor.ShaderGraph;
using UnityEditor.ShaderGraph.Drawing.Controls;
using UnityEditor.ShaderGraph.Internal;
using UnityEngine.Rendering.Universal;
using System.Reflection;
using System.Linq;

namespace UnityEditor.Rendering.Universal
{
    [SRPFilter(typeof(UniversalRenderPipeline))]
    [Title("Input", "Universal", "Universal Sample Buffer")]
    sealed class UniversalSampleBufferNode : AbstractMaterialNode, IGeneratesBodyCode, IGeneratesFunction, IMayRequireScreenPosition, IMayRequireDepthTexture
    {
        const string k_ScreenPositionSlotName = "UV";
        const string k_OutputSlotName = "Output";
        const string k_SamplerInputSlotName = "Sampler";

        const int k_ScreenPositionSlotId = 0;
        const int k_OutputSlotId = 2;
        public const int k_SamplerInputSlotId = 3;

        public enum BufferType
        {
            NormalWorldSpace,
            MotionVectors,
            // PostProcessInput,
            BlitSource,
        }

        [SerializeField]
        private BufferType m_BufferType = BufferType.NormalWorldSpace;

        [EnumControl("Source Buffer")]
        public BufferType bufferType
        {
            get { return m_BufferType; }
            set
            {
                if (m_BufferType == value)
                    return;

                m_BufferType = value;
                Dirty(ModificationScope.Graph);
            }
        }

        public override string documentationURL => Documentation.GetPageLink("SGNode-Universal-Sample-Buffer");

        public UniversalSampleBufferNode()
        {
            name = "Universal Sample Buffer";
            synonyms = new string[] { "normal", "motion vector", "postprocessinput", "blit" };
            UpdateNodeAfterDeserialization();
        }

        public override bool hasPreview { get { return true; } }
        public override PreviewMode previewMode => PreviewMode.Preview2D;

        int channelCount;

        public sealed override void UpdateNodeAfterDeserialization()
        {
            AddSlot(new ScreenPositionMaterialSlot(k_ScreenPositionSlotId, k_ScreenPositionSlotName, k_ScreenPositionSlotName, ScreenSpaceType.Default));
            AddSlot(new SamplerStateMaterialSlot(k_SamplerInputSlotId, k_SamplerInputSlotName, k_SamplerInputSlotName, SlotType.Input));

            switch (bufferType)
            {
                case BufferType.NormalWorldSpace:
                    AddSlot(new Vector3MaterialSlot(k_OutputSlotId, k_OutputSlotName, k_OutputSlotName, SlotType.Output, Vector3.zero, ShaderStageCapability.Fragment));
                    channelCount = 3;
                    break;
                case BufferType.MotionVectors:
                    AddSlot(new Vector2MaterialSlot(k_OutputSlotId, k_OutputSlotName, k_OutputSlotName, SlotType.Output, Vector2.zero, ShaderStageCapability.Fragment));
                    channelCount = 2;
                    break;
                // case BufferType.PostProcessInput:
                case BufferType.BlitSource:
                    AddSlot(new ColorRGBAMaterialSlot(k_OutputSlotId, k_OutputSlotName, k_OutputSlotName, SlotType.Output, Color.black, ShaderStageCapability.Fragment));
                    channelCount = 4;
                    break;
            }

            RemoveSlotsNameNotMatching(new[]
            {
                k_ScreenPositionSlotId,
                k_SamplerInputSlotId,
                k_OutputSlotId,
            });
        }

        public override void CollectShaderProperties(PropertyCollector properties, GenerationMode generationMode)
        {
            if (generationMode.IsPreview())
                return;

            if (bufferType == BufferType.BlitSource)
            {
                properties.AddShaderProperty(new Texture2DArrayShaderProperty
                {
                    // Make it compatible with Blitter.cs calls
                    overrideReferenceName = "_BlitTexture",
                    displayName = "_BlitTexture",
                    hidden = true,
                    generatePropertyBlock = true,
                    isMainTexture = true,
                });
            }
            // else if (bufferType == BufferType.PostProcessInput)
            // {
            //     properties.AddShaderProperty(new Texture2DArrayShaderProperty
            //     {
            //         overrideReferenceName = nameof(HDShaderIDs._CustomPostProcessInput),
            //         displayName = nameof(HDShaderIDs._CustomPostProcessInput),
            //         hidden = true,
            //         generatePropertyBlock = true,
            //         isMainTexture = true,
            //     });
            // }
        }

        string GetFunctionName() => "Unity_Universal_SampleBuffer_$precision";

        public void GenerateNodeFunction(FunctionRegistry registry, GenerationMode generationMode)
        {
            // Preview SG doesn't have access to render pipeline buffer
            if (!generationMode.IsPreview())
            {
                registry.ProvideFunction(GetFunctionName(), s =>
                {
                    // Default sampler when the sampler slot is not connected.
                    s.AppendLine("SAMPLER(s_linear_clamp_sampler);");

                    s.AppendLine("#include \"Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl\"");

                    // s.AppendLine("#include \"Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Builtin/BuiltinData.hlsl\"");

                    s.AppendLine("$precision{1} {0}($precision2 uv, SamplerState samplerState)", GetFunctionName(), channelCount);
                    using (s.BlockScope())
                    {
                        switch (bufferType)
                        {
                            case BufferType.NormalWorldSpace:
                                s.AppendLine("return SampleSceneNormals(uv);");
                                break;
                            case BufferType.MotionVectors:
                                // if we have a value > 1.0f, it means we have selected the "no motion option", hence we force motionVec 0.
                                s.AppendLine($"float4 motionVecBufferSample = SAMPLE_TEXTURE2D_X_LOD(_CameraMotionVectorsTexture, samplerState, uv * _RTHandleScale.xy, 0);");
                                s.AppendLine("float2 motionVec;");
                                s.AppendLine("DecodeMotionVector(motionVecBufferSample, motionVec);");
                                s.AppendLine("return motionVec;");
                                break;
                            // case BufferType.PostProcessInput:
                            //     s.AppendLine("return SAMPLE_TEXTURE2D_X_LOD(_CustomPostProcessInput, samplerState, uv * _RTHandlePostProcessScale.xy, 0);");
                            //     break;
                            case BufferType.BlitSource:
                                s.AppendLine($"return SAMPLE_TEXTURE2D_X_LOD(_MainTex, samplerState, uv, 0); ");
                                break;
                            default:
                                s.AppendLine("return 0.0;");
                                break;
                        }
                    }
                });
            }
        }

        public void GenerateNodeCode(ShaderStringBuilder sb, GenerationMode generationMode)
        {
            if (generationMode.IsPreview())
            {
                sb.AppendLine($"$precision{channelCount} {GetVariableNameForSlot(k_OutputSlotId)} = 0.0;");
            }
            else
            {
                string uv = GetSlotValue(k_ScreenPositionSlotId, generationMode);
                var samplerSlot = FindInputSlot<MaterialSlot>(k_SamplerInputSlotId);
                var edgesSampler = owner.GetEdges(samplerSlot.slotReference);
                var sampler = edgesSampler.Any() ? $"{GetSlotValue(k_SamplerInputSlotId, generationMode)}.samplerstate" : "s_linear_clamp_sampler";
                sb.AppendLine($"$precision{channelCount} {GetVariableNameForSlot(k_OutputSlotId)} = {GetFunctionName()}({uv}.xy, {sampler});");
            }
        }

        public bool RequiresDepthTexture(ShaderStageCapability stageCapability) => true;

        public bool RequiresScreenPosition(ShaderStageCapability stageCapability = ShaderStageCapability.All) => true;
    }
}
