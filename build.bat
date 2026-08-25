@echo off

if not exist build mkdir build


pushd build
odin build ..\source\platform_sdl3\ -out:nbtfinder.exe -debug
popd
