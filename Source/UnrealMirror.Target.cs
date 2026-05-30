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
            string shell;
            if (OperatingSystem.IsWindows())
            {
                shell = "pwsh ";
            }
            else if (OperatingSystem.IsMacOS())
            {
                // macOSのUnreal Editorはとても基本的な環境で動作しており、pwshを直接起動するのが難しい。
                // zshをログインシェルとして起動することでパスをセットアップし、pwshを見つけられるようにする。
                shell = "zsh -lc ";
            }
            else
            {
                shell = "";
            }
            return shell + "\"$(ProjectDir)/Tool/VRM4U/setup.ps1\"";
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
