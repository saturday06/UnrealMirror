// SPDX-License-Identifier: Apache-2.0

#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"

#include "AutoScreenshotSubsystem.generated.h"

UCLASS()
class UNREALMIRROR_API UAutoScreenshotSubsystem : public UWorldSubsystem {
  GENERATED_BODY()

public:
  virtual void OnWorldBeginPlay(UWorld &InWorld) override;

private:
  FTimerHandle ScreenshotTimerHandle;
  FTimerHandle ExitTimerHandle;

  void TakeScreenshotAndExit();
};
