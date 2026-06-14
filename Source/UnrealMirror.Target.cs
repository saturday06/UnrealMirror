// Copyright Epic Games, Inc. All Rights Reserved.

#nullable enable

using System;
using UnrealBuildTool;

public class UnrealMirrorTarget : TargetRules
{
    public static string? SetupPrerequisitesCommand
    {
        get
        {
            string cdCommand;
            if (OperatingSystem.IsWindows())
            {
                cdCommand = "cd /d \"$(ProjectDir)\\Tool\\dotnet\"";
            }
            else if (OperatingSystem.IsMacOS() || OperatingSystem.IsLinux())
            {
                cdCommand = "cd \"$(ProjectDir)/Tool/dotnet\"";
            }
            else
            {
                return null;
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
        if (SetupPrerequisitesCommand is { } setupPrerequisitesCommand)
        {
            PreBuildSteps.Add(setupPrerequisitesCommand);
        }
    }
}
