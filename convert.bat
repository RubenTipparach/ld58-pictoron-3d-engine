@echo off
REM FBX/OBJ to Lua Converter Batch Script
REM Usage: convert.bat <input.fbx|input.obj> [output.lua]

if "%~1"=="" (
    echo Usage: convert.bat ^<input.fbx^|input.obj^> [output.lua]
    echo.
    echo Example:
    echo   convert.bat building.fbx
    echo   convert.bat model.obj custom_output.lua
    exit /b 1
)

python fbx_to_lua.py %*
