// Copyright Epic Games, Inc. All Rights Reserved.

using System;
using System.Collections.Generic;
using UnrealBuildTool;

public class UnrealMirrorTarget : TargetRules
{
    public static string Vrm4uSetupCommand
    {
        get
        {
            string cdCommand;
            if (OperatingSystem.IsWindows())
            {
                cdCommand = "cd /d \"$(ProjectDir)/Tool\"";
            }
            else
            {
                cdCommand = "cd \"$(ProjectDir)/Tool\"";
            }
            string dotnetCommand =
                "dotnet tool restore && dotnet tool run pwsh -- "
                + " setup.ps1 "
                + " -TargetPlatform \"$(TargetPlatform)\" "
                + " -TargetConfiguration \"$(TargetConfiguration)\" "
                + " -TargetType \"$(TargetType)\" ";

            return cdCommand + " && " + dotnetCommand;
        }
    }

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
