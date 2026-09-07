package platform_sdl3
import "../nbtfinder"

import "core:os"
import "base:runtime"
import "core:strings"
import "core:fmt"

import "vendor:sdl3"
import mu "vendor:microui"

PlatformState :: struct {
  window : ^sdl3.Window,
  renderer : ^sdl3.Renderer,

  mu_atlas_texture : ^sdl3.Texture,
  mu_context : ^mu.Context
}

platstate : PlatformState = {}

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

AppInit :: proc "c" (appstate: ^rawptr, argc: i32, argv: [^]cstring) -> sdl3.AppResult {
  context = runtime.default_context()

  fmt.print(size_of(nbtfinder.Nbt_TagValue))

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


    platstate.renderer = sdl3.CreateRenderer(platstate.window, nil)
    if (platstate.renderer == nil) {
      fmt.eprintfln("Failed to initialize renderer, SDL_ERROR: %s", sdl3.GetError())
      return sdl3.AppResult.FAILURE
    }

    if (microui_prep() == false) {
      return sdl3.AppResult.FAILURE
    }
  }

  // DESC: app init
  {
    memory, err := new(nbtfinder.AppState)
    if (err != .None) {
      return sdl3.AppResult.FAILURE
    }
    appstate^ = memory;

    mu_context, ok := nbtfinder.init(memory);
    if (!ok) {
      return sdl3.AppResult.FAILURE
    }
    platstate.mu_context = mu_context
  }


  nbtfinder.Mca_read("r.0.0.mca")

  app_result := sdl3.AppResult.CONTINUE
  return app_result
}

AppIterate :: proc "c" (appstate: rawptr) -> sdl3.AppResult {
  context = runtime.default_context()

  microui_render(cast(^nbtfinder.AppState)appstate)

  app_result := sdl3.AppResult.CONTINUE
  return app_result
}

AppQuit :: proc "c" (appstate: rawptr, result: sdl3.AppResult) {
  context = runtime.default_context()

  free(appstate);
}

AppEvent :: proc "c" (appstate: rawptr, event: ^sdl3.Event) -> sdl3.AppResult {
  context = runtime.default_context()

  microui_process_event(event)
  #partial switch event.type {
  case .QUIT:
    return sdl3.AppResult.SUCCESS
  }

  app_result := sdl3.AppResult.CONTINUE
  return app_result
}

