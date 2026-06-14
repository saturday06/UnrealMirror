// Copyright Epic Games, Inc. All Rights Reserved.

#nullable enable

using UnrealBuildTool;

public class UnrealMirror : ModuleRules
{
    public UnrealMirror(ReadOnlyTargetRules Target)
        : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        bEnableExceptions = true;

        PublicDependencyModuleNames.AddRange(
            new string[] { "Core", "CoreUObject", "Engine", "InputCore", "EnhancedInput" }
        );

        PrivateDependencyModuleNames.AddRange(
            new string[]
            {
                "Boost",
                "ImageWrapper",
                "RenderCore",
                "VRM4U",
                "VRM4ULoader",
                "Slate",
                "SlateCore",
            }
        );
    }
}
