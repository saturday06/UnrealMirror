// Copyright Epic Games, Inc. All Rights Reserved.

using System.Collections.Generic;
using UnrealBuildTool;

public class UnrealMirrorEditorTarget : TargetRules
{
    public UnrealMirrorEditorTarget(TargetInfo Target)
        : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("UnrealMirror");
        PreBuildSteps.Add(UnrealMirrorTarget.Vrm4uSetupCommand);
    }
}
