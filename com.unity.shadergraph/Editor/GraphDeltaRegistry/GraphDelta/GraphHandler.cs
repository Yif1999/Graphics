using System;
using System.Collections.Generic;
using UnityEditor.ShaderGraph.Registry;
using UnityEditor.ContextLayeredDataStorage;
using UnityEngine;

namespace UnityEditor.ShaderGraph.GraphDelta
{
    public class GraphHandler
    {
        internal GraphDelta graphDelta;

        public GraphHandler()
        {
            graphDelta = new GraphDelta();
        }

        public GraphHandler(string serializedData)
        {
            graphDelta = new GraphDelta(serializedData);
        }

        public string ToSerializedFormat()
        {
            return EditorJsonUtility.ToJson(graphDelta.m_data, true);
        }

        internal NodeHandler AddNode<T>(string name, Registry.Registry registry) where T : Registry.Defs.INodeDefinitionBuilder => graphDelta.AddNode<T>(name, registry);

        public NodeHandler AddNode(RegistryKey key, string name, Registry.Registry registry) => graphDelta.AddNode(key, name, registry);
        public NodeHandler AddContextNode(RegistryKey key, Registry.Registry registry) => graphDelta.AddContextNode(key, registry);
        public bool ReconcretizeNode(string name, Registry.Registry registry) => graphDelta.ReconcretizeNode(name, registry);

        [Obsolete]
        public NodeHandler GetNodeReader(string name) => graphDelta.GetNode(name);
        [Obsolete]
        public NodeHandler GetNodeWriter(string name) => graphDelta.GetNode(name);

        public NodeHandler GetNode(string name) => graphDelta.GetNode(name);
        public void RemoveNode(string name) => graphDelta.RemoveNode(name);
        public IEnumerable<NodeHandler> GetNodes() => graphDelta.GetNodes();

        public IEdgeHandler AddEdge(ElementID src, ElementID dst) => graphDelta.AddEdge(src, dst);

        //public TargetRef AddTarget(TargetType targetType)

        //public void RemoveTarget(TargetRef targetRef)

        //public List<TargetSetting> GetTargetSettings(TargetRef targetRef)

        //public INodeWriter AddNode(NodeType nodeType)

        //public void RemoveNode(INodeRef nodeRef);

        //public NodeType GetNodeType(NodeRef nodeRef)

        //public IEnumerable<INodeReader> GetNodes();

        //public IEnumerable<IPortReader> GetOutputPorts(INodeReader nodeRef);

        //public bool CanConnect(PortRef outputPort, PortRef inputPort)

        //public ConnectionRef Connect(PortRef outputPort, PortRef inputPort)

        //public ConnectionRef ForceConnect(PortRef outputPort, PortRef inputPort)

        //public List<ConnectionRef> GetConnections(PortRef portRef)

        //public void RemoveConnection(ConnectionRef connectionRef)
    }
}
