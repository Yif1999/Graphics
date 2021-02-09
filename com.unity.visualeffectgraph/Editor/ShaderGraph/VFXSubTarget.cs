using System;
using UnityEditor.ShaderGraph;

namespace UnityEditor.VFX
{
    static class VFXSubTarget
    {
        // TODO: Find a safer way to track this state
        private static bool                   s_Configured;
        private static VFXContext             s_Context;
        private static VFXContextCompiledData s_Data;

        static class VFXFields
        {
            public const string kTag = "PrimitiveType";
            public static FieldDescriptor ParticleMesh            = new FieldDescriptor(kTag, "Mesh",            "VFX_PARTICLE_MESH 1");
            public static FieldDescriptor ParticlePlanarPrimitive = new FieldDescriptor(kTag, "PlanarPrimitive", "VFX_PARTICLE_PLANAR_PRIMITIVE 1");
        }

        public static event Func<SubShaderDescriptor, VFXContext, VFXContextCompiledData, SubShaderDescriptor> OnPostProcessSubShader;

        internal class CompilationScope : IDisposable
        {
            internal CompilationScope(VFXContext context, VFXContextCompiledData data)
            {
                s_Configured = true;
                s_Context    = context;
                s_Data       = data;
            }

            public void Dispose()
            {
                s_Configured = false;
                s_Context    = null;
            }
        }

        internal static bool IsConfigured() => s_Configured;

        internal static SubShaderDescriptor PostProcessSubShader(SubShaderDescriptor descriptor)
        {
            // TODO: Move generic VFX sub shader processing in here and break up the callback into SRP-specific portions (like FragInputs struct).
            return OnPostProcessSubShader?.Invoke(descriptor, s_Context, s_Data) ?? descriptor;
        }

        internal static void GetFields(ref TargetFieldContext fieldsContext)
        {
            fieldsContext.AddField(Fields.GraphVFX, IsConfigured());

            if (!IsConfigured())
                return;

            // Support the various context primitive types.
            switch (s_Context.taskType)
            {
                case VFXTaskType.ParticleMeshOutput:
                    fieldsContext.AddField(VFXFields.ParticleMesh);
                    break;
                case VFXTaskType.ParticleTriangleOutput:
                case VFXTaskType.ParticleOctagonOutput:
                case VFXTaskType.ParticleQuadOutput:
                    fieldsContext.AddField(VFXFields.ParticlePlanarPrimitive);
                    break;
            }
        }
    }
}
