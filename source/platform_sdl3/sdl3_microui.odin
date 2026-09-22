package platform_sdl3
// NOTE(dendo): not sure how to proprly architecture the UI, shouldn't be skiping handmade lessons

import "../nbtfinder"
import "../nbtfinder/ui"

import "core:fmt"
import "vendor:sdl3"
import mu "vendor:microui"


mustate :: struct {
  ctx : mu.Context,
  atlas_texture : ^sdl3.Texture,
}

state : mustate

// NOTE: Copyed and modified from https://github.com/odin-lang/examples/blob/master/sdl3/microui/microui_sdl_demo.odin
microui_init :: proc () -> (ok: bool) {
  mu.init(&state.ctx)

  state.ctx.text_width  = mu.default_atlas_text_width
  state.ctx.text_height = mu.default_atlas_text_height

  state.atlas_texture = sdl3.CreateTexture(platstate.renderer, .RGBA32, .TARGET, mu.DEFAULT_ATLAS_WIDTH, mu.DEFAULT_ATLAS_HEIGHT)
  assert(state.atlas_texture != nil)
  if !sdl3.SetTextureBlendMode(state.atlas_texture, {.BLEND}) {
    fmt.eprintln("SDL.SetTextureBlendMode: %s", sdl3.GetError())
    return false
  }

  pixels := make([][4]u8, mu.DEFAULT_ATLAS_WIDTH*mu.DEFAULT_ATLAS_HEIGHT)
  for alpha, i in mu.default_atlas_alpha {
    pixels[i].rgb = 0xff
    pixels[i].a   = alpha
  }

  if !sdl3.UpdateTexture(state.atlas_texture, nil, raw_data(pixels), 4*mu.DEFAULT_ATLAS_WIDTH) {
    fmt.eprintln("SDL.UpdateTexture: %s", sdl3.GetError())
    return false
  }

  delete(pixels)

  return true
}

microui_process_event :: proc (event: ^sdl3.Event) {
  #partial switch event.type {
  case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
    fn := mu.input_mouse_down if event.button.down else mu.input_mouse_up
    switch event.button.button {
    case 1:
      fn(&state.ctx, i32(event.button.x), i32(event.button.y), .LEFT)
    case 2:
      fn(&state.ctx, i32(event.button.x), i32(event.button.y), .MIDDLE)
    case 3:
      fn(&state.ctx, i32(event.button.x), i32(event.button.y), .RIGHT)
    }
  case .MOUSE_MOTION:
    mu.input_mouse_move(&state.ctx, i32(event.motion.x), i32(event.motion.y))
  case .MOUSE_WHEEL:
    mu.input_scroll(&state.ctx, i32(event.wheel.x * 16), i32(event.wheel.y * -16))
  }
}

microui_render_draw_commands :: proc "contextless" (mu_ctx : ^mu.Context) {
	render_texture :: proc "contextless" (renderer: ^sdl3.Renderer, dst: ^sdl3.FRect, src: mu.Rect, color: mu.Color) {
		dst.w = f32(src.w)
		dst.h = f32(src.h)

		sdl3.SetTextureAlphaMod(state.atlas_texture, color.a)
		sdl3.SetTextureColorMod(state.atlas_texture, color.r, color.g, color.b)
		sdl3.RenderTexture(renderer, state.atlas_texture, &sdl3.FRect{f32(src.x), f32(src.y), f32(src.w), f32(src.h)}, dst)
	}

	viewport_rect := &sdl3.Rect{}
	sdl3.GetRenderOutputSize(platstate.renderer, &viewport_rect.w, &viewport_rect.h)
	sdl3.SetRenderViewport(platstate.renderer, viewport_rect)
	sdl3.SetRenderClipRect(platstate.renderer, viewport_rect)
	sdl3.SetRenderDrawColor(platstate.renderer, 30, 0, 0, 0)
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

microui_render :: proc (appstate : ^nbtfinder.AppState) {
  ctx := &state.ctx

  viewport_rect := &sdl3.Rect{}
  sdl3.GetRenderOutputSize(platstate.renderer, &viewport_rect.w, &viewport_rect.h)
  mu_rect : mu.Rect = {
    x = viewport_rect.x, y = viewport_rect.y,
    w = viewport_rect.w, h = viewport_rect.h
  }

  ui.microui_draw_commands(ctx, appstate, mu_rect)
  microui_render_draw_commands(ctx)

}

microui_fini :: proc () {
  sdl3.DestroyTexture(state.atlas_texture)

}

