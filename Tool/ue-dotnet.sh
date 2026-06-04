#!/bin/sh

set -eu

cd "$(dirname "$0")"

engine_association=$(python3 -c "import json; import pathlib; print(json.loads(pathlib.Path('UnrealMirror.uproject').read_text())['EngineAssociation'])")
echo "Not implemented: Reading Unreal Engine root path from registry on Linux/MacOS. EngineAssociation: $engine_association"
