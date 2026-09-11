@echo off

if not exist build mkdir build

if "%1"=="release" (
  set "arg=-o:speed"
) else (
  set "arg="
)

if "%2"=="asm" (
  set "arg2=-build-mode:asm"
) else (
  set "arg2="
)


pushd build
odin build ..\source\platform_sdl3\ -debug -out:nbtfinder.exe %arg% %arg2%
popd
