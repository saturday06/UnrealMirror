# SPDX-License-Identifier: Apache-2.0
#Requires -Version 5.1

[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$BuildArguments = @(),

  [string]$GameExePath = $env:UNREAL_MIRROR_APP_EXE,

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
Set-StrictMode -Version 2

function Find-UnrealMirrorExe {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRootPath
  )

  $searchRoots = @(
    (Join-Path $ProjectRootPath "ArchivedBuilds"),
    (Join-Path $ProjectRootPath "Saved\StagedBuilds")
  )

  foreach ($searchRoot in $searchRoots) {
    if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) {
      continue
    }

    $candidate = Get-ChildItem -LiteralPath $searchRoot -Recurse -Filter "UnrealMirror.exe" -File -ErrorAction SilentlyContinue |
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

$toolRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRootPath = (Resolve-Path (Join-Path $toolRootPath "..")).Path
$buildScriptPath = Join-Path $toolRootPath "build.bat"

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
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  if ([string]::IsNullOrWhiteSpace($GameExePath)) {
    $GameExePath = Find-UnrealMirrorExe -ProjectRootPath $projectRootPath
  }

  if ([string]::IsNullOrWhiteSpace($GameExePath)) {
    throw "UnrealMirror.exe was not found under ArchivedBuilds or Saved\StagedBuilds. Set -GameExePath or UNREAL_MIRROR_APP_EXE."
  }

  $resolvedGameExePath = (Resolve-Path $GameExePath).Path
  if (-not (Test-Path -LiteralPath $resolvedGameExePath -PathType Leaf)) {
    throw "Game executable was not found: $resolvedGameExePath"
  }

  $screenshotDirectory = Split-Path -Parent $ScreenshotPath
  if (-not (Test-Path -LiteralPath $screenshotDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $screenshotDirectory | Out-Null
  }

  $launchTime = Get-Date
  Write-Output "Using VRM: $VrmPath"
  Write-Output "Starting UnrealMirror: $resolvedGameExePath $($GameArguments -join ' ')"
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $resolvedGameExePath
  $startInfo.WorkingDirectory = Split-Path -Parent $resolvedGameExePath
  $startInfo.UseShellExecute = $false
  $startInfo.Arguments = ($GameArguments | ForEach-Object { ConvertTo-CommandLineArgument -Argument $_ }) -join " "
  $startInfo.EnvironmentVariables["UNREAL_MIRROR_SCREENSHOT_PATH"] = $ScreenshotPath
  $startInfo.EnvironmentVariables["UNREAL_MIRROR_VRM_PATH"] = $VrmPath

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

  if (-not (Test-Path -LiteralPath $ScreenshotPath -PathType Leaf)) {
    throw "Screenshot was not created: $ScreenshotPath"
  }

  $screenshot = Get-Item -LiteralPath $ScreenshotPath
  if ($screenshot.LastWriteTime -lt $launchTime.AddSeconds(-2)) {
    throw "Screenshot exists but was not updated by this run: $ScreenshotPath"
  }

  Write-Output "Screenshot saved: $ScreenshotPath"
}
finally {
  Pop-Location
}
