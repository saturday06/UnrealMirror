#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.6

param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$BuildArguments = @(),

  [string]$ScreenshotPath,

  [string]$VrmPath,

  [string[]]$GameArguments = @(
    "-ResX=512",
    "-ResY=512",
    "-Windowed",
    "-AllowSoftwareRendering",
    "-stdout",
    "-FullStdOutLogOutput"
  )
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

function Find-UnrealMirrorExe {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRootPath
  )

  if ($IsMacOS) {
    return Join-Path `
      -Path `
      "Saved" `
      -ChildPath `
      "StagedBuilds", `
      "Mac", `
      "UnrealMirror-Mac-Shipping.app", `
      "Contents", `
      "MacOS", `
      "UnrealMirror-Mac-Shipping"
  }

  $searchRoots = @(
    (Join-Path $ProjectRootPath "ArchivedBuilds"),
    (Join-Path $ProjectRootPath "Saved\StagedBuilds")
  )

  if ($IsWindows) {
    $exeExt = ".exe"
  }
  else {
    $exeExt = ""
  }

  foreach ($searchRoot in $searchRoots) {
    if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) {
      continue
    }

    $candidate = Get-ChildItem -LiteralPath $searchRoot -Recurse -Filter "UnrealMirror${exeExt}" -File -ErrorAction SilentlyContinue |
    Sort-Object -Property LastWriteTime -Descending |
    Select-Object -First 1

    if ($null -ne $candidate) {
      return $candidate.FullName
    }
  }

  return $null
}

function ConvertTo-CommandLineArgument {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Argument
  )

  if ($Argument -notmatch '[\s"]') {
    return $Argument
  }

  return '"' + ($Argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Save-FileFromUrl {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
  )

  $downloadDirectory = Split-Path -Parent $DestinationPath
  if (-not (Test-Path -LiteralPath $downloadDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $downloadDirectory | Out-Null
  }

  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing
}

$projectRootPath = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath "..", "..")).Path
$buildScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "run-uat-build-cook-run.ps1"

if ([string]::IsNullOrWhiteSpace($ScreenshotPath)) {
  $ScreenshotPath = Join-Path $projectRootPath "screenshot.png"
}
elseif (-not [System.IO.Path]::IsPathRooted($ScreenshotPath)) {
  $ScreenshotPath = Join-Path $projectRootPath $ScreenshotPath
}
$ScreenshotPath = [System.IO.Path]::GetFullPath($ScreenshotPath)

if ([string]::IsNullOrWhiteSpace($VrmPath)) {
  $VrmPath = Join-Path (Split-Path -Parent $ScreenshotPath) "sample.vrm"
}
elseif (-not [System.IO.Path]::IsPathRooted($VrmPath)) {
  $VrmPath = Join-Path $projectRootPath $VrmPath
}
$VrmPath = [System.IO.Path]::GetFullPath($VrmPath)

if (-not (Test-Path -LiteralPath $VrmPath -PathType Leaf)) {
  $seedSanUrl = "https://raw.githubusercontent.com/vrm-c/vrm-specification/c24d76d99a18738dd2c266be1c83f089064a7b5e/samples/Seed-san/vrm/Seed-san.vrm"
  Write-Output "Downloading sample VRM: $seedSanUrl"
  Save-FileFromUrl -Url $seedSanUrl -DestinationPath $VrmPath
}

if (-not (Test-Path -LiteralPath $buildScriptPath -PathType Leaf)) {
  throw "Build script was not found: $buildScriptPath"
}

Push-Location $projectRootPath
try {
  Write-Output "Building UnrealMirror with $buildScriptPath"
  & $buildScriptPath @BuildArguments
  $buildExitCode = $LASTEXITCODE
  if ($buildExitCode -ne 0) {
    Write-Output "UnrealMirror build failed with code $buildExitCode; skipping application launch."
    exit $buildExitCode
  }

  $gameExePath = Find-UnrealMirrorExe -ProjectRootPath $projectRootPath

  if ([string]::IsNullOrWhiteSpace($gameExePath)) {
    throw "UnrealMirror.exe was not found under ArchivedBuilds or Saved\StagedBuilds. Set -GameExePath or UNREAL_MIRROR_APP_EXE."
  }

  $resolvedGameExePath = (Resolve-Path $gameExePath).Path
  if (-not (Test-Path -LiteralPath $resolvedGameExePath -PathType Leaf)) {
    throw "Game executable was not found: $resolvedGameExePath"
  }

  $screenshotDirectory = Split-Path -Parent $ScreenshotPath
  if (-not (Test-Path -LiteralPath $screenshotDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $screenshotDirectory | Out-Null
  }

  $runtimeVrmPath = $VrmPath
  $runtimeScreenshotPath = $ScreenshotPath
  $sandboxRunDirectory = $null
  if ($IsMacOS) {
    $appContentsPath = Split-Path -Parent (Split-Path -Parent $resolvedGameExePath)
    $infoPlistPath = Join-Path $appContentsPath "Info.plist"
    $bundleId = (& /usr/bin/plutil -extract CFBundleIdentifier raw -o - $infoPlistPath).Trim()
    if ($bundleId -notmatch '^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$') {
      throw "Invalid app bundle identifier in ${infoPlistPath}: $bundleId"
    }

    # App Sandbox permits the game to read/write its own container. Keep each
    # run separate so an earlier screenshot cannot make a failed run pass.
    $userProfilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    $sandboxRunDirectory = Join-Path -Path $userProfilePath -ChildPath `
      "Library", "Containers", $bundleId, "Data", "Library", "Caches", `
      "UnrealMirrorDevRun", ([Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $sandboxRunDirectory -Force | Out-Null
    $runtimeVrmPath = Join-Path $sandboxRunDirectory "input.vrm"
    $runtimeScreenshotPath = Join-Path $sandboxRunDirectory "screenshot.png"
    Copy-Item -LiteralPath $VrmPath -Destination $runtimeVrmPath
    Write-Output "Sandbox run directory: $sandboxRunDirectory"
  }

  $launchTime = Get-Date
  Write-Output "Using VRM: $VrmPath"
  Write-Output "Starting UnrealMirror: $resolvedGameExePath $($GameArguments -join ' ')"
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $resolvedGameExePath
  $startInfo.WorkingDirectory = Split-Path -Parent $resolvedGameExePath
  $startInfo.UseShellExecute = $false
  $startInfo.Arguments = ($GameArguments | ForEach-Object { ConvertTo-CommandLineArgument -Argument $_ }) -join " "
  $startInfo.EnvironmentVariables["UNREAL_MIRROR_SCREENSHOT_PATH"] = $runtimeScreenshotPath
  $startInfo.EnvironmentVariables["UNREAL_MIRROR_VRM_PATH"] = $runtimeVrmPath

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  if (-not $process.Start()) {
    throw "Failed to start UnrealMirror: $resolvedGameExePath"
  }

  $process.WaitForExit()
  $gameExitCode = $process.ExitCode

  Write-Output "UnrealMirror exited with code $gameExitCode"
  if ($gameExitCode -ne 0) {
    exit $gameExitCode
  }

  if (-not (Test-Path -LiteralPath $runtimeScreenshotPath -PathType Leaf)) {
    throw "Screenshot was not created: $runtimeScreenshotPath"
  }

  $screenshot = Get-Item -LiteralPath $runtimeScreenshotPath
  if ($screenshot.LastWriteTime -lt $launchTime.AddSeconds(-2)) {
    throw "Screenshot exists but was not updated by this run: $runtimeScreenshotPath"
  }
  if ($screenshot.Length -eq 0) {
    throw "Screenshot is empty: $runtimeScreenshotPath"
  }

  if ($null -ne $sandboxRunDirectory) {
    Copy-Item -LiteralPath $runtimeScreenshotPath -Destination $ScreenshotPath -Force
    # Retain failed runs for diagnosis; remove only this run after successful export.
    Remove-Item -LiteralPath $sandboxRunDirectory -Recurse -Force -ErrorAction Continue
  }

  Write-Output "Screenshot saved: $ScreenshotPath"
}
finally {
  Pop-Location
}
