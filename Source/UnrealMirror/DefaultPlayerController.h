// SPDX-License-Identifier: Apache-2.0

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"

#include "DefaultPlayerController.generated.h"

/**
 *
 */
UCLASS()
class UNREALMIRROR_API ADefaultPlayerController : public APlayerController {
  GENERATED_BODY()
protected:
  virtual void BeginPlay() override;
};
