package platform_sdl3
import "../nbtfinder"

import "core:os"
import "base:runtime"
import "core:strings"
import "core:fmt"
import "core:time"
import si "core:sys/info"

import "vendor:sdl3"
import "vendor:sdl3/ttf"
import mu "vendor:microui"

import win "core:sys/windows"

PlatformState :: struct {
  window : ^sdl3.Window,
  renderer : ^sdl3.Renderer,

  text_engine: ^ttf.TextEngine,
}

platstate : PlatformState = {}


// DESC(dendo): ui intefaces

NBTFINDER_UI :: #config(NBTFINDER_UI, "microui")

when NBTFINDER_UI == "microui" {
  ui_init   : proc() -> (ok: bool)                : microui_init
  ui_render : proc(appstate: ^nbtfinder.AppState) -> (keep_updating: bool) : microui_render
  ui_event  : proc(event: ^sdl3.Event)            : microui_process_event
  ui_fini   : proc()                              : microui_fini
} else when NBTFINDER_UI == "clay" {
  ui_init   : proc() -> (ok: bool)                : clay_init
  ui_render : proc(appstate: ^nbtfinder.AppState) -> (keep_updating: bool) : clay_render
  ui_event  : proc(event: ^sdl3.Event)            : clay_process_event
  ui_fini   : proc()                              : clay_fini
} else {
message :: "ui '" + NBTFINDER_UI + "' not implemented on platform"
#panic(message)
}


main :: proc () {
  argv : []cstring = make([]cstring, len(os.args))
  for i := 0; i < len(os.args); i += 1 {
    argv[i] = strings.clone_to_cstring(os.args[i])
  }

  // NOTE(dendo): There might be little benefit to using the SDL3 callbacks
  // TODO(dendo): maybe investigate this later
  ret := sdl3.EnterAppMainCallbacks(
    i32(len(os.args)),
    &argv[0],
    AppInit,
    AppIterate,
    AppEvent,
    AppQuit
  )
  os.exit(int(ret))
}

DialogFileCallback :: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: i32) {
  appstate: ^nbtfinder.AppState = (^nbtfinder.AppState)(userdata)

  context = runtime.default_context()


  nbtfinder.stage_files(appstate, filelist)
}

AppInit :: proc "c" (appstate: ^rawptr, argc: i32, argv: [^]cstring) -> sdl3.AppResult {
  context = runtime.default_context()

  // NOTE(dendo): prety lazy fix to make windows tolerate utf8 on the terminal
  {
    when ODIN_OS == .Windows {
      win.SetConsoleOutputCP(win.CODEPAGE.UTF8)
    }
  }

  // DESC: plataform init
  {
    width := i32(nbtfinder.window_specs.width)
    height := i32(nbtfinder.window_specs.height)
    flags := sdl3.WINDOW_RESIZABLE
    platstate.window = sdl3.CreateWindow(cstring(nbtfinder.window_specs.title), width, height, flags)
    if (platstate.window == nil) {
      fmt.eprintfln("Failed to initialize window, SDL_ERROR: %s", sdl3.GetError())
      return sdl3.AppResult.FAILURE
    }

    if (!sdl3.SetHint(sdl3.HINT_MAIN_CALLBACK_RATE, "60")) {
      fmt.eprintfln("Failed to set main callback rate, SDL_ERROR: %s", sdl3.GetError())
      return sdl3.AppResult.FAILURE
    }

    platstate.renderer = sdl3.CreateRenderer(platstate.window, nil)
    if (platstate.renderer == nil) {
      fmt.eprintfln("Failed to initialize renderer, SDL_ERROR: %s", sdl3.GetError())
      return sdl3.AppResult.FAILURE
    }

    if ttf.Init() != true {
      fmt.eprintfln("Failed to init TTF, SDL_ERROR: %v", sdl3.GetError())
      return sdl3.AppResult.FAILURE
    }

    platstate.text_engine = ttf.CreateRendererTextEngine(platstate.renderer)
    if platstate.text_engine == nil {
      fmt.eprintfln("Failed to create TTF_TextEngine, SDL_ERROR: %v", sdl3.GetError())
      return sdl3.AppResult.FAILURE
    }

    if (ui_init() == false) {
      return sdl3.AppResult.FAILURE
    }
  }

  cpu_features : nbtfinder.CPU_Features
  {
    when ODIN_ARCH == .amd64 {
      cpu_features += { .SIMD_128_bits }

      avx2_test := si.CPU_Features{ .avx, .avx2 }
      if avx2_test <= si.cpu_features() {
        cpu_features += { .SIMD_256_bits }
      }

      avx512_test := si.CPU_Features{ .avx512f, .avx512vl, .avx512dq, .avx512bw }
      if avx512_test <= si.cpu_features() {
        cpu_features += { .SIMD_512_bits }
      }
    }

  }

  // DESC: app init
  {
    memory, err := new(nbtfinder.AppState)
    if (err != .None) {
      return sdl3.AppResult.FAILURE
    }
    appstate^ = memory;

    ok := nbtfinder.init(memory, cpu_features);
    if (!ok) {
      return sdl3.AppResult.FAILURE
    }

    
    //sdl3.ShowOpenFolderDialog(DialogFileCallback, platstate, platstate.window, nil, false)

  }



  app_result := sdl3.AppResult.CONTINUE
  return app_result
}

AppIterate :: proc "c" (_appstate: rawptr) -> sdl3.AppResult {
  context = runtime.default_context()

  appstate := cast(^nbtfinder.AppState)_appstate

  tick := time.tick_now()

  {
    keep_updating := ui_render(appstate)

    if keep_updating {
      sdl3.SetHint(sdl3.HINT_MAIN_CALLBACK_RATE, "60")
    } else {
      sdl3.SetHint(sdl3.HINT_MAIN_CALLBACK_RATE, "waitevent")
    }
  }

  free_all(context.temp_allocator)

  frame_duration := time.tick_since(tick)
  nbtfinder.update_last_frame_duration(appstate, frame_duration)

  app_result := sdl3.AppResult.CONTINUE
  return app_result
}

AppQuit :: proc "c" (appstate: rawptr, result: sdl3.AppResult) {
  context = runtime.default_context()

  free(appstate);
}

AppEvent :: proc "c" (appstate: rawptr, event: ^sdl3.Event) -> sdl3.AppResult {
  context = runtime.default_context()

  ui_event(event)
  #partial switch event.type {
  case .KEY_DOWN:
    key := event.key
    if key.key == sdl3.K_O && (key.mod & { .LCTRL, .RCTRL } != {}) {
      sdl3.ShowOpenFileDialog(
        DialogFileCallback,
        (^nbtfinder.AppState)(appstate),
        platstate.window,
        nil,
        0,
        nil,
        true,
      )
    }
  case .QUIT:
    return sdl3.AppResult.SUCCESS
  }

  app_result := sdl3.AppResult.CONTINUE
  return app_result
}

