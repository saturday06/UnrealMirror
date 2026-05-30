// SPDX-License-Identifier: Apache-2.0

#include "DefaultGameModeBase.h"

#include "DefaultPlayerController.h"

ADefaultGameModeBase::ADefaultGameModeBase() {
  PlayerControllerClass = ADefaultPlayerController::StaticClass();
}
