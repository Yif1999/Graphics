﻿using System;

namespace UnityEngine.Rendering.UIGen
{
    public struct DataBind/*<T>*/ : UIDefinition.IFeatureParameter
    {
        string bindingPath;
        //public readonly Func<T> get;
        //public readonly Action<T> set;
    }
}
