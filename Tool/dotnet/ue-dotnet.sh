#!/usr/bin/env bash

set -eu -o pipefail

engine_major_minor_version=$(
  python3 - "$(dirname "$0")/../../Plugins/VRM4U/VRM4U.uplugin" <<'ENGINE_MAJOR_MINOR_VERSION'
import json
import pathlib
import sys
uplugin_path = pathlib.Path(sys.argv[1])
uplugin = json.loads(uplugin_path.read_text())
engine_version = uplugin['EngineVersion']
engine_major_minor_version = '.'.join(engine_version.split('.')[:2])
print(engine_major_minor_version)
ENGINE_MAJOR_MINOR_VERSION
)

if [ -z "$engine_major_minor_version" ]; then
  echo 'Failed to get engine version from VRM4U.uplugin' >&2
  exit 1
fi

uname_system=$(uname -s)

case "$uname_system" in
Darwin)
  if [ -z "${UE_ROOT:-}" ]; then
    UE_ROOT="/Users/Shared/Epic Games/UE_${engine_major_minor_version}/Engine/Build/BatchFiles"
  fi
  batch_files_platform_path="${UE_ROOT}/Mac"
  ;;
Linux)
  if [ -z "${UE_ROOT:-}" ]; then
    echo 'Please set the "UE_ROOT" environment variable' >&2
    echo 'See https://dev.epicgames.com/documentation/unreal-engine/linux-development-quickstart-for-unreal-engine?application_version=5.7#5b-build-a-project-through-the-command-line' >&2
    exit 1
  fi
  batch_files_platform_path="${UE_ROOT}/Linux"
  ;;
*)
  echo "Unsupported platform: ${uname_system}" >&2
  exit 1
  ;;
esac

setup_environment_sh_path="${batch_files_platform_path}/SetupEnvironment.sh"
if [ ! -f "$setup_environment_sh_path" ]; then
  echo "Failed to find SetupEnvironment.sh at ${setup_environment_sh_path}" >&2
  exit 1
fi

set +eu
# shellcheck disable=SC1090
. "$setup_environment_sh_path" -dotnet "$batch_files_platform_path"
set -eu

export DOTNET_CLI_TELEMETRY_OPTOUT=1
exec dotnet "$@"
