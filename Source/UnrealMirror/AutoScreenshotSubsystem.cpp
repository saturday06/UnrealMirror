// SPDX-License-Identifier: Apache-2.0

#include "AutoScreenshotSubsystem.h"

#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "HAL/PlatformMisc.h"
#include "TimerManager.h"
#include "UnrealClient.h"

DEFINE_LOG_CATEGORY_STATIC(LogUnrealMirrorScreenshot, Log, All);

void UAutoScreenshotSubsystem::OnWorldBeginPlay(UWorld &InWorld) {
  Super::OnWorldBeginPlay(InWorld);

  if (!InWorld.IsGameWorld()) {
    return;
  }

  InWorld.GetTimerManager().SetTimer(
      ScreenshotTimerHandle, this,
      &UAutoScreenshotSubsystem::TakeScreenshotAndExit, 10.0f, false);
}

void UAutoScreenshotSubsystem::TakeScreenshotAndExit() {
  UWorld *World = GetWorld();
  if (!World) {
    return;
  }

  const FString ScreenshotPath = FPlatformMisc::GetEnvironmentVariable(
      TEXT("UNREAL_MIRROR_SCREENSHOT_PATH"));
  if (ScreenshotPath.IsEmpty()) {
    UE_LOG(LogUnrealMirrorScreenshot, Error,
           TEXT("UNREAL_MIRROR_SCREENSHOT_PATH is not set; skipping "
                "screenshot."));
    if (GEngine) {
      GEngine->DeferredCommands.Add(TEXT("quit"));
    }
    return;
  }

  FScreenshotRequest::RequestScreenshot(ScreenshotPath, false, false);

  World->GetTimerManager().SetTimer(
      ExitTimerHandle,
      []() {
        if (GEngine) {
          GEngine->DeferredCommands.Add(TEXT("quit"));
        }
      },
      0.5f, false);
}
