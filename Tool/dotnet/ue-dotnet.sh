#!/usr/bin/env bash

set -eu -o pipefail

engine_association=$(
  python3 - "$(dirname "$0")/../../UnrealMirror.uproject" <<ENGINE_ASSOCIATION
import json
import pathlib
import sys
uproject_path = pathlib.Path(sys.argv[1])
uproject = json.loads(uproject_path.read_text())
print(uproject['EngineAssociation'])
ENGINE_ASSOCIATION
)

if [ -z "$engine_association" ]; then
  echo 'Failed to get EngineAssociation from UnrealMirror.uproject' >&2
  exit 1
fi

uname_system=$(uname -s)

case "$uname_system" in
Darwin)
  if [ -z "${UE_ROOT:-}" ]; then
    UE_ROOT="/Users/Shared/Epic Games/UE_${engine_association}/Engine/Build/BatchFiles"
  fi
  ;;
Linux)
  if [ -z "${UE_ROOT:-}" ]; then
    echo 'Please set the "UE_ROOT" environment variable' >&2
    echo 'See https://dev.epicgames.com/documentation/unreal-engine/linux-development-quickstart-for-unreal-engine#5b-build-a-project-through-the-command-line' >&2
    exit 1
  fi
  ;;
*)
  echo "Unsupported platform: ${uname_system}" >&2
  exit 1
  ;;
esac

setup_environment_sh_path="${UE_ROOT}/SetupEnvironment.sh"
if [ ! -f "$setup_environment_sh_path" ]; then
  echo "Failed to find SetupEnvironment.sh at ${setup_environment_sh_path}" >&2
  exit 1
fi

set +eu
# shellcheck disable=SC1090
. "$setup_environment_sh_path" -dotnet "$UE_ROOT"
set -eu

exec dotnet "$@"
