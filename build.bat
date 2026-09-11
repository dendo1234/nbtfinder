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

set "extra=-microarch:znver4"


pushd build
odin build ..\source\platform_sdl3\ -debug %extra% -out:nbtfinder.exe %arg% %arg2%
popd
