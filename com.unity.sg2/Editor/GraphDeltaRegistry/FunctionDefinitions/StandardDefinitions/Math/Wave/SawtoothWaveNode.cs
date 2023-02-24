using Usage = UnityEditor.ShaderGraph.GraphDelta.GraphType.Usage;

namespace UnityEditor.ShaderGraph.Defs
{
    internal class SawtoothWaveNode : IStandardNode
    {
        public static string Name => "SawtoothWave";
        public static int Version => 1;

        public static FunctionDescriptor FunctionDescriptor => new(
            Name,
            "Out = 2 * (In - floor(0.5 + In));",
            new ParameterDescriptor[]
            {
                new ParameterDescriptor("In", TYPE.Vector, Usage.In),
                new ParameterDescriptor("Out", TYPE.Vector, Usage.Out)
            }
        );

        public static NodeUIDescriptor NodeUIDescriptor => new(
            Version,
            Name,
            displayName: "Sawtooth Wave",
            tooltip: "creates a wave form with a slow, linear ramp up and then an instant drop",
            category: "Math/Wave",
            synonyms: new string[1] { "triangle wave" },
            description: "pkg://Documentation~/previews/SawtoothWave.md",
            parameters: new ParameterUIDescriptor[2] {
                new ParameterUIDescriptor(
                    name: "In",
                    displayName: string.Empty,
                    tooltip: "input value"
                ),
                new ParameterUIDescriptor(
                    name: "Out",
                    displayName: string.Empty,
                    tooltip: "a sawtooth wave"
                )
            }
        );
    }
}
