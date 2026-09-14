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

REM set "features=-target-features:avx,avx2,avx512f,avx512bw,avx512vl,avx512dq"


pushd build
odin build ..\source\platform_sdl3\ -debug %features% %arg% %arg2% -out:nbtfinder.exe 
popd
