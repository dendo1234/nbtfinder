@echo off

if not exist build mkdir build

set uprof_path="%ProgramFiles%\AMD\AMDuProf"

set has_uprof=0
if exist %uprof_path% set has_uprof=1

if not "%1"=="uprof" (
  set has_uprof=0
)

set "compiler_args="
set "compiler_args=%compiler_args% -collection:clay=..\external\clay\bindings\odin"
set "compiler_args=%compiler_args% -define:NBTFINDER_UI=clay"
REM set "compiler_args=%compiler_args% -vet"

if %has_uprof% EQU 1 (
  set uprof_args=-define:HAS_UPROF=true -collection:uprof=%uprof_path% -extra-linker-flags:"/nodefaultlib:libcmt /defaultlib:ucrt.lib shell32.lib"
) else (
  REM NOTE(dendo): frustating. Odin doesn't like collections with invalid paths.
  REM I wonder if there is a better way to pass paths to it.
  REM The alternative is including the uprof library into the repo, which is a bit dumb
  set "uprof_args=-define:HAS_UPROF=false -collection:uprof=."
)

set "compiler_args=%compiler_args% %uprof_args%"

if "%1"=="release" (
  set "compiler_args=%compiler_args% -o:speed"
) else if "%1"=="print" (
  set "compiler_args=%compiler_args% -print-linker-flags"
)

if "%2"=="release" (
  set "compiler_args=%compiler_args% -o:speed"
)

REM set "features=-target-features:avx,avx2,avx512f,avx512bw,avx512vl,avx512dq"

pushd build
odin build ..\source\platform_sdl3\ -debug %features% %compiler_args% -out:nbtfinder.exe
popd
