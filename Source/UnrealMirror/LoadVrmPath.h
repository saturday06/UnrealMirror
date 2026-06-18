// VRM4U Copyright (c) 2021-2026 Haruyoshi Yamamoto. This software is released
// under the MIT License. ApplicationLifecycleComponent.:  See FCoreDelegates
// for details

#pragma once

#include "Components/ActorComponent.h"
#include "CoreMinimal.h"
#include "Misc/CoreDelegates.h"
#include "UObject/ObjectMacros.h"

#include "LoadVrmPath.generated.h"

/** Component to handle receiving notifications from the OS about application
 * state (activated, suspended, termination, etc). */
UCLASS(ClassGroup = Utility, HideCategories = (Activation, "Components|Activation", Collision),
	   meta = (BlueprintSpawnableComponent))
class UNREALMIRROR_API ULoadVrmPathComponent : public UActorComponent
{
	GENERATED_UCLASS_BODY()

	DECLARE_MULTICAST_DELEGATE_OneParam(FStaticOnDropFiles, FString);
	static FStaticOnDropFiles StaticOnDropFilesDelegate;

	DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnDropFiles, FString, FileName);

	UPROPERTY(BlueprintAssignable)
	FOnDropFiles OnDropFiles;

	static ULoadVrmPathComponent *s_LatestActiveComponent;

public:
	void OnRegister() override;
	void OnUnregister() override;

	static const ULoadVrmPathComponent *getLatestActiveComponent()
	{
		return s_LatestActiveComponent;
	};

	UFUNCTION(BlueprintCallable, Category = "Unreal Mirror")
	bool VRMGetOpenFileName(FString &Filename);

private:
	void OnDropFilesDelegate_Handler(FString FileName)
	{
		OnDropFiles.Broadcast(FileName);
	}
};
