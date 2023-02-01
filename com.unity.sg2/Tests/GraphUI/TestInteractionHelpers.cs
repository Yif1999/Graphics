﻿using System.Collections;
using System.Collections.Generic;
using NUnit.Framework;
using Unity.GraphToolsFoundation.Editor;
using Unity.ItemLibrary.Editor;
using UnityEngine;

namespace UnityEditor.ShaderGraph.GraphUI.UnitTests
{
    /// <summary>
    /// Meant to hold any higher level graph UI interactions that will be commonly used in tests
    /// </summary>
    class TestInteractionHelpers
    {
        private readonly TestEditorWindow _window;
        private readonly TestEventHelpers _testEventHelper;

        public TestInteractionHelpers(TestEditorWindow targetWindow, TestEventHelpers testEventHelper)
        {
            _window = targetWindow;
            _testEventHelper = testEventHelper;
        }

        public IEnumerator SelectAndCopyNodes(List<AbstractNodeModel> nodeModels)
        {
            // Select both the nodes
            _window.GraphView.Dispatch(new SelectElementsCommand(SelectElementsCommand.SelectionMode.Replace, nodeModels));
            yield return null;

            _testEventHelper.SimulateKeyPress("C", modifiers: EventModifiers.Control);
            yield return null;

            _testEventHelper.SimulateKeyPress("V", modifiers: EventModifiers.Control);
            yield return null;
        }

        public void ConnectNodes(string fromNodeName, string toNodeName, string fromPortName = "Out", string toPortName = "In")
        {
            var fromNode = _window.GetNodeModelFromGraphByName(fromNodeName);
            var fromPortModel = SGGraphModel.FindOutputPortByName(fromNode, fromPortName);

            var toNode = _window.GetNodeModelFromGraphByName(toNodeName);
            var toPortModel =  SGGraphModel.FindInputPortByName(toNode, toPortName);

            _window.GraphView.Dispatch(new CreateWireCommand(toPortModel, fromPortModel));
        }
    }
}
