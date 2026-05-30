// SPDX-License-Identifier: Apache-2.0

#include "DefaultPlayerController.h"

void ADefaultPlayerController::BeginPlay() {
  Super::BeginPlay();

  bShowMouseCursor = true;
}
