@echo off

if not exist build mkdir build

set "compiler_args="
set "compiler_args=%compiler_args% -collection:clay=..\external\clay\bindings\odin"
set "compiler_args=%compiler_args% -define:NBTFINDER_UI=clay"

if "%1"=="release" (
  set "compiler_args=%compiler_args% -o:speed"
) else (
  set "arg="
)


REM set "features=-target-features:avx,avx2,avx512f,avx512bw,avx512vl,avx512dq"

pushd build
odin build ..\source\platform_sdl3\ -debug %features% %compiler_args% -out:nbtfinder.exe
popd
