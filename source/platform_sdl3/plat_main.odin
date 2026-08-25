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

  mu_atlas_texture : ^sdl3.Texture
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

    // DESC: microui init
    // NOTE: Copyed and modified from https://github.com/odin-lang/examples/blob/master/sdl3/microui/microui_sdl_demo.odin
    {
      platstate.mu_atlas_texture = sdl3.CreateTexture(platstate.renderer, .RGBA32, .TARGET, mu.DEFAULT_ATLAS_WIDTH, mu.DEFAULT_ATLAS_HEIGHT)
      assert(platstate.mu_atlas_texture != nil)
      if !sdl3.SetTextureBlendMode(platstate.mu_atlas_texture, {.BLEND}) {
        fmt.eprintln("SDL.SetTextureBlendMode: %s", sdl3.GetError())
        return sdl3.AppResult.FAILURE
      }

      pixels := make([][4]u8, mu.DEFAULT_ATLAS_WIDTH*mu.DEFAULT_ATLAS_HEIGHT)
      for alpha, i in mu.default_atlas_alpha {
        pixels[i].rgb = 0xff
        pixels[i].a   = alpha
      }

      if !sdl3.UpdateTexture(platstate.mu_atlas_texture, nil, raw_data(pixels), 4*mu.DEFAULT_ATLAS_WIDTH) {
        fmt.eprintln("SDL.UpdateTexture: %s", sdl3.GetError())
        return sdl3.AppResult.FAILURE
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

    ok := nbtfinder.init(memory);
    if (!ok) {
      return sdl3.AppResult.FAILURE
    }
  }



  //nbtfinder.Mca_read("r.0.0.mca")

  app_result := sdl3.AppResult.CONTINUE
  return app_result
}

AppIterate :: proc "c" (appstate: rawptr) -> sdl3.AppResult {
  context = runtime.default_context()

  mu_ctx := nbtfinder.render(cast(^nbtfinder.AppState)appstate)
  render_microui(mu_ctx)

  app_result := sdl3.AppResult.CONTINUE
  return app_result
}

AppQuit :: proc "c" (appstate: rawptr, result: sdl3.AppResult) {
  context = runtime.default_context()

  free(appstate);
}

AppEvent :: proc "c" (appstate: rawptr, event: ^sdl3.Event) -> sdl3.AppResult {
  app_result := sdl3.AppResult.CONTINUE

  return app_result
}

// NOTE: Copyed and modified from https://github.com/odin-lang/examples/blob/master/sdl3/microui/microui_sdl_demo.odin
render_microui :: proc "contextless" (mu_ctx : ^mu.Context) {
	render_texture :: proc "contextless" (renderer: ^sdl3.Renderer, dst: ^sdl3.FRect, src: mu.Rect, color: mu.Color) {
		dst.w = f32(src.w)
		dst.h = f32(src.h)

		sdl3.SetTextureAlphaMod(platstate.mu_atlas_texture, color.a)
		sdl3.SetTextureColorMod(platstate.mu_atlas_texture, color.r, color.g, color.b)
		sdl3.RenderTexture(renderer, platstate.mu_atlas_texture, &sdl3.FRect{f32(src.x), f32(src.y), f32(src.w), f32(src.h)}, dst)
	}

	viewport_rect := &sdl3.Rect{}
	sdl3.GetRenderOutputSize(platstate.renderer, &viewport_rect.w, &viewport_rect.h)
	sdl3.SetRenderViewport(platstate.renderer, viewport_rect)
	sdl3.SetRenderClipRect(platstate.renderer, viewport_rect)
	sdl3.SetRenderDrawColor(platstate.renderer, 0, 0, 0, 0)
	sdl3.RenderClear(platstate.renderer)

	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(mu_ctx, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Text:
			dst := sdl3.FRect{f32(cmd.pos.x), f32(cmd.pos.y), 0, 0}
			for ch in cmd.str {
				if ch&0xc0 != 0x80 {
					r := min(int(ch), 127)
					src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
					render_texture(platstate.renderer, &dst, src, cmd.color)
					dst.x += dst.w
				}
			}
		case ^mu.Command_Rect:
			sdl3.SetRenderDrawColor(platstate.renderer, cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
			sdl3.RenderFillRect(platstate.renderer, &sdl3.FRect{f32(cmd.rect.x), f32(cmd.rect.y), f32(cmd.rect.w), f32(cmd.rect.h)})
		case ^mu.Command_Icon:
			src := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - src.w)/2
			y := cmd.rect.y + (cmd.rect.h - src.h)/2
			render_texture(platstate.renderer, &sdl3.FRect{f32(x), f32(y), 0, 0}, src, cmd.color)
		case ^mu.Command_Clip:
			sdl3.SetRenderClipRect(platstate.renderer, &sdl3.Rect{cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h})
		case ^mu.Command_Jump:
			unreachable()
		}
	}

	sdl3.RenderPresent(platstate.renderer)
}
