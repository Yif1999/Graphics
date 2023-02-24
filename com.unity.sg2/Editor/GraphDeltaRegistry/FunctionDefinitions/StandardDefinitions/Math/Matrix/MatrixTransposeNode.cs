using Usage = UnityEditor.ShaderGraph.GraphDelta.GraphType.Usage;

namespace UnityEditor.ShaderGraph.Defs
{
    internal class MatrixTransposeNode : IStandardNode
    {
        public static string Name => "MatrixTranspose";
        public static int Version => 1;

        public static FunctionDescriptor FunctionDescriptor => new(
            Name,
            "Out = transpose(In);",
            new ParameterDescriptor[]
            {
                new ParameterDescriptor("In", TYPE.Matrix, Usage.In, new float[] { 1f, 0f, 0f, 1f}),
                new ParameterDescriptor("Out", TYPE.Matrix, Usage.Out)
            }
        );

        public static NodeUIDescriptor NodeUIDescriptor => new(
            Version,
            Name,
            displayName: "Matrix Transpose",
            tooltip: "Calculates the transposed value of the input matrix.",
            category: "Math/Matrix",
            synonyms: new string[1] { "Transpose" },
            hasPreview: false,
            description: "pkg://Documentation~/previews/MatrixTranspose.md",
            parameters: new ParameterUIDescriptor[2] {
                new ParameterUIDescriptor(
                    name: "In",
                    displayName: string.Empty,
                    tooltip: "input matrix"
                ),
                new ParameterUIDescriptor(
                    name: "Out",
                    displayName: string.Empty,
                    tooltip: "the transposed value of the input matrix"
                )
            }
        );
    }
}
