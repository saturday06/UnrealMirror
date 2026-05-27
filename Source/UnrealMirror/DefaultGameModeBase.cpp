// Fill out your copyright notice in the Description page of Project Settings.

#include "DefaultGameModeBase.h"

#include "DefaultPlayerController.h"

ADefaultGameModeBase::ADefaultGameModeBase() {
  PlayerControllerClass = ADefaultPlayerController::StaticClass();
}
