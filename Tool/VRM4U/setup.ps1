#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$cmake = "cmake"
if ($IsWindows) {
  $cmakeGenerator = "Visual Studio 17 2022"
  $vsVersionRange = "[17.0,18.0)"
  $vcVersion = "vc143"

  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe was not found: $vswhere"
  }
  $vsInstallationPath = & $vswhere -version $vsVersionRange -property installationPath
  if (-not $vsInstallationPath) {
    throw "Visual Studio was not found"
  }
  $cmake = Join-Path -Path $vsInstallationPath -ChildPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
}
elseif ($IsMacOS) {
  $cmakeGenerator = "Xcode"
  $cmake = (Get-Command cmake).Source
}
else {
  $cmakeGenerator = "Unix Makefiles"
  $cmake = (Get-Command cmake).Source
}

if (-not (Test-Path $cmake)) {
  throw "cmake.exe was not found: $cmake"
}

$assimpSourceFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "assimp"
if (-not (Test-Path (Join-Path -Path $assimpSourceFolderPath -ChildPath "Readme.md"))) {
  git -C $PSScriptRoot submodule update --init --recursive
}

$debugAssimpBuildFolderPath = Join-Path -Path $assimpSourceFolderPath -ChildPath "build" -AdditionalChildPath "Debug"
New-Item -ItemType Directory $debugAssimpBuildFolderPath -Force

$releaseAssimpBuildFolderPath = Join-Path -Path $assimpSourceFolderPath -ChildPath "build" -AdditionalChildPath "Release"
New-Item -ItemType Directory $releaseAssimpBuildFolderPath -Force

$buildSharedLibs = $IsWindows ? "ON" : "OFF"
$vrm4uAssimpFolderPath = Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "..", "Plugins", "VRM4U", "ThirdParty", "assimp"

New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64") -Force
New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Debug") -Force
New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Release") -Force

if (-not (Test-Path (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "CMakeCache.txt"))) {
  & $cmake `
    -G $cmakeGenerator `
    -DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF `
    -DASSIMP_WARNINGS_AS_ERRORS=OFF `
    "-DBUILD_SHARED_LIBS=${buildSharedLibs}" `
    -DCMAKE_BUILD_TYPE=Debug `
    -B $debugAssimpBuildFolderPath `
    -S $assimpSourceFolderPath
}
& $cmake --build $debugAssimpBuildFolderPath --config Debug
if ($IsWindows) {
  Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Debug", "assimp-${vcVersion}-mtd.dll") (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64")
  Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Debug", "assimp-${vcVersion}-mtd.pdb") (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64")
  Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Debug", "assimp-${vcVersion}-mtd.lib") (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Debug")
}
elseif ($IsMacOS) {
  Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Debug", "libassimpd.a") (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "Mac", "libassimpd.a")
}

if (-not (Test-Path (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "CMakeCache.txt"))) {
  & $cmake `
    -G $cmakeGenerator `
    -DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF `
    -DASSIMP_WARNINGS_AS_ERRORS=OFF `
    "-DBUILD_SHARED_LIBS=${buildSharedLibs}" `
    -DCMAKE_BUILD_TYPE=Release `
    -B $releaseAssimpBuildFolderPath `
    -S $assimpSourceFolderPath
}
& $cmake --build $releaseAssimpBuildFolderPath --config Release

if ($IsWindows) {
  Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.dll") (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64")
  Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.pdb") (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64")
  Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.lib") (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Release")
}
elseif ($IsMacOS) {
  Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Release", "libassimp.a") (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "Mac", "libassimp.a")
}

$vrm4uAssimpIncludeFolderPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "include" -AdditionalChildPath "assimp"
Remove-Item $vrm4uAssimpIncludeFolderPath -Recurse -Force
New-Item -ItemType Directory -Path $vrm4uAssimpIncludeFolderPath -Force
Copy-Item (Join-Path -Path $assimpSourceFolderPath -ChildPath "include" -AdditionalChildPath "assimp", "*") $vrm4uAssimpIncludeFolderPath -Recurse -Force
Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "include" -AdditionalChildPath "assimp", "*") $vrm4uAssimpIncludeFolderPath -Recurse -Force
