// Copyright Epic Games, Inc. All Rights Reserved.

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

        // Uncomment if you are using online features
        // PrivateDependencyModuleNames.Add("OnlineSubsystem");

        // To include OnlineSubsystemSteam, add it to the plugins section in your uproject file with the Enabled attribute set to true
    }
}
