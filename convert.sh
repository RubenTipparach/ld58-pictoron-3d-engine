#!/bin/bash
# FBX/OBJ to Lua Converter Script
# Usage: convert.sh <input.fbx|input.obj> [output.lua]

if [ -z "$1" ]; then
    echo "Usage: convert.sh <input.fbx|input.obj> [output.lua]"
    echo ""
    echo "Example:"
    echo "  convert.sh building.fbx"
    echo "  convert.sh model.obj custom_output.lua"
    exit 1
fi

python3 fbx_to_lua.py "$@"
