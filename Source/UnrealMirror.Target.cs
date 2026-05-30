// Copyright Epic Games, Inc. All Rights Reserved.

using System.Collections.Generic;
using UnrealBuildTool;

public class UnrealMirrorTarget : TargetRules
{
    public static readonly string Vrm4uSetupCommand = "pwsh \"$(ProjectDir)/Tool/VRM4U/setup.ps1\"";

    public UnrealMirrorTarget(TargetInfo Target)
        : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("UnrealMirror");
        PreBuildSteps.Add(Vrm4uSetupCommand);
    }
}
