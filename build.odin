package build_script

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:flags"

Build_Options :: struct {
  ndebug: bool,
  speed: bool,
  print: bool,
  uprof: bool,
	msvc: bool
}

main :: proc() {
  loc: runtime.Source_Code_Location
  if err := build(&loc); err != nil {
    fmt.eprintfln("error while building(%v): %v", loc, err)
  }
}

build :: proc(exit: ^runtime.Source_Code_Location) -> (err: os.Error) {
	defer {
		exit ^= #branch_location
	}

  options: Build_Options

  if len(os.args) > 1 {
    flags.parse_or_exit(&options, os.args)
  }

	directory := os.get_executable_directory(context.allocator) or_return
	defer delete(directory)
	os.set_working_directory(directory) or_return

  out_folder := fmt.tprintf("build/%v/", ODIN_OS)
  if !os.exists(out_folder) {
    os.make_directory_all(out_folder) or_return
  }

  command: [dynamic]string

  append(&command, "odin")
  append(&command, "build")
  append(&command, "source/nbtfinder")

	if options.msvc {
		append(&command, "-linker:msvc")
	}
	
  if !options.ndebug {
    append(&command, "-debug")
  }

  if options.speed {
    append(&command, "-o:speed")
  }

  append(&command, "-collection:clay=external/clay/bindings/odin")
  append(&command, "-define:NBTFINDER_UI=clay")

  uprof_path: string
  when ODIN_OS == .Windows {
    uprof_path = os.replace_environment_placeholders(`%ProgramFiles%\AMD\AMDuProf`, context.allocator)
    defer free(raw_data(uprof_path))
  }

  if os.exists(uprof_path) && options.uprof {
    uprof_collection := fmt.tprintf("-collection:uprof=%s", uprof_path)
    append(&command, uprof_collection)

    when ODIN_OS == .Windows {
      append(&command, "-extra-linker-flags:/nodefaultlib:libcmt /defaultlib:ucrt.lib shell32.lib")
    }

    append(&command, "-define:HAS_UPROF=true")

  } else {
    append(&command, "-collection:uprof=.")
    append(&command, "-define:HAS_UPROF=false")
  }

  out_path := fmt.tprintf("-out:%vnbtfinder.exe", out_folder)
  append(&command, out_path)

  if options.print {
    fmt.print("odin")
    for i in command[1:] {
      fmt.printf(" %v", i)
    }
    fmt.println()
  }

  desc: os.Process_Desc = {
    command = command[:],
    stdout = os.stdout,
    stderr = os.stderr,
    stdin = os.stdin,
  }

  process := os.process_start(desc) or_return

  state := os.process_wait(process) or_return

  assert(state.exited)

  fi := os.read_all_directory_by_path("data/copy", context.allocator) or_return

  for file_info in fi {
    link_name := fmt.tprintf("%v%v", out_folder, file_info.name)

    if !os.exists(link_name) {
      // NOTE: os.link is prefered because windows symlinks
      os.link(file_info.fullpath, link_name) or_return
    }
  }

  return nil
}


