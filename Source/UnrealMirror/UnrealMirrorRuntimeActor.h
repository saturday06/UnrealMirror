// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"

#include "UnrealMirrorRuntimeActor.generated.h"

class UDirectionalLightComponent;
class USceneCaptureComponent2D;
class USceneComponent;
class USkeletalMeshComponent;
class UTextureRenderTarget2D;
class UVrmAssetListObject;

UCLASS()
class AUnrealMirrorRuntimeActor : public AActor {
  GENERATED_BODY()

public:
  AUnrealMirrorRuntimeActor();

  bool LoadVrmModel(const FString &Path, FString &OutMessage);
  bool LoadVrmAnimation(const FString &Path, FString &OutMessage);
  bool CapturePngScreenshot(const FString &Path, FString &OutMessage);

private:
  void FrameLoadedModel();
  void EnsureRenderTarget();

  UPROPERTY()
  TObjectPtr<USceneComponent> SceneRoot;

  UPROPERTY()
  TObjectPtr<USkeletalMeshComponent> MeshComponent;

  UPROPERTY()
  TObjectPtr<USceneCaptureComponent2D> CaptureComponent;

  UPROPERTY()
  TObjectPtr<UDirectionalLightComponent> KeyLightComponent;

  UPROPERTY()
  TObjectPtr<UTextureRenderTarget2D> RenderTarget;

  UPROPERTY()
  TObjectPtr<UVrmAssetListObject> VrmAsset;
};
