
using System;
using System.Collections.Generic;
using Unity.GraphToolsFoundation.Editor;
using UnityEditor.ShaderGraph.GraphDelta;
using UnityEngine;
using Unity.GraphToolsFoundation;
using Object = UnityEngine.Object;

namespace UnityEditor.ShaderGraph.GraphUI
{
    [Serializable]
    abstract class BaseShaderGraphConstant : Constant, ICopyPasteCallbackReceiver
    {
        [SerializeField]
        protected string nodeName;

        [SerializeField]
        protected string portName;

        [SerializeReference]
        List<BakedElement> m_CopyPasteData;

        SGGraphModel graphModel => OwnerModel?.GraphModel as SGGraphModel;

        GraphHandler graphHandler => graphModel?.GraphHandler;

        // TODO: shouldn't need to special case if we're a searcher preview.
        NodeHandler nodeHandler => graphHandler?.GetNode(nodeName)
            ?? graphModel.RegistryInstance.DefaultTopologies.GetNode(nodeName);

        public bool IsBound => !string.IsNullOrEmpty(nodeName) && !string.IsNullOrEmpty(portName) && graphHandler != null && nodeHandler != null;

        protected FieldHandler GetField()
        {
            if (!IsBound) return null;
            try
            {
                var portReader = nodeHandler.GetPort(portName);
                var typeField = portReader?.GetTypeField();
                return typeField;
            }
            catch (Exception e)
            {
                Debug.LogException(e);
                return null;
            }
        }

        public string NodeName => nodeName;

        public string PortName => portName;

        public override object ObjectValue
        {
            get
            {
                Debug.Assert(graphModel != null);
                Debug.Assert(IsBound);

                return IsBound ? GetValue() : DefaultValue;
            }
            set
            {
                Debug.Assert(graphModel != null);
                Debug.Assert(IsBound);

                if (IsBound)
                {
                    OwnerModel?.GraphModel?.CurrentGraphChangeDescription?.AddChangedModel(OwnerModel, ChangeHint.Data);
                    SetValue(value);
                }
            }
        }

        public virtual void BindTo(string nodeName, string portName)
        {
            this.nodeName = nodeName;
            this.portName = portName;
        }

        protected abstract object GetValue();

        protected abstract void SetValue(object value);

        public override void Initialize(TypeHandle constantTypeHandle) { }

        public override Constant Clone()
        {
            var copy = (BaseShaderGraphConstant)Activator.CreateInstance(GetType());
            copy.BindTo(nodeName, portName);
            return copy;
        }

        /// <inheritdoc />
        public virtual void OnBeforeCopy()
        {
            m_CopyPasteData?.Clear();
            m_CopyPasteData ??= new();
            var portReader = nodeHandler.GetPort(portName);
            BakedElement.BakePort(portReader, m_CopyPasteData);
        }

        /// <inheritdoc />
        public virtual void OnAfterPaste()
        {
            var portReader = nodeHandler.GetPort(portName);
            BakedElement.UnbakePort(m_CopyPasteData, portReader);
            m_CopyPasteData.Clear();
        }
    }
}
