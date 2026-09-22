package platform_sdl3

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:strings"
import "base:runtime"
import "vendor:sdl3"
import "vendor:sdl3/ttf"
import clay "clay:clay-odin"

import "../nbtfinder"
import "../nbtfinder/ui"

/*
ui_fini   :: proc()
*/

Clay_State :: struct {
  is_left_mouse_down: bool,
  mouse_x: f32,
  mouse_y: f32,

  image: ^sdl3.Texture,

  fonts: [4]^ttf.Font
}

claystate : Clay_State

// NOTE: copied and modified from https://github.com/nicbarker/clay/blob/main/bindings/odin/README.md

clay_init :: proc() -> (ok: bool) {
  error_handler :: proc "c" (errorData: clay.ErrorData) {
    context = runtime.default_context()
    length := errorData.errorText.length
    chars := errorData.errorText.chars
    str := strings.string_from_ptr(chars, int(length))
    fmt.eprintfln("Clay Error: %v", str)
  }

  min_memory_size := clay.MinMemorySize()
  memory := make([^]u8, min_memory_size)
  arena: clay.Arena = clay.CreateArenaWithCapacityAndMemory(uint(min_memory_size), memory)
  clay.Initialize(arena, {1080, 720}, { handler = error_handler })

  // Example measure text function
  measure_text :: proc "c" (
    text: clay.StringSlice,
    config: ^clay.TextElementConfig,
    userData: rawptr,
  ) -> clay.Dimensions {
    // clay.TextElementConfig contains members such as fontId, fontSize, letterSpacing, etc..
    // Note: clay.String->chars is not guaranteed to be null terminated


    // TODO: this is not considering
    // letterSpacing: u16,
    // lineHeight:    u16,
    // wrapMode:      TextWrapMode,
    // textAlignment: TextAlignment,

    // TODO: do this properly
    /*
    ttf.SetFontSize(claystate.fonts[config.fontId], f32(config.fontSize))
    width: i32
    ttf.MeasureString(claystate.fonts[config.fontId], cstring(text.chars), uint(text.length), 0, &width,nil)
    */
    

    return {
      width = f32(text.length * i32(config.fontSize)),
      height = f32(config.fontSize),
    }
  }

  // Tell clay how to measure text
  clay.SetMeasureTextFunction(measure_text, nil)

  claystate.image = sdl3.CreateTexture(platstate.renderer, .RGBA8888, .STATIC, 400, 300)
  if claystate.image == nil {
    fmt.eprintfln("Failed to create SDL_Texture: %v", sdl3.GetError())
    return false
  }

  DejaVuSans :: #load("../../data/DejaVuSans.ttf")

  dejavu_stream := sdl3.IOFromMem(raw_data(DejaVuSans), len(DejaVuSans))
  assert(dejavu_stream != nil)
  claystate.fonts[0] = ttf.OpenFontIO(dejavu_stream, true, 12)
  if (claystate.fonts[0] == nil) {
    fmt.eprintfln("Failed to create Font: %v", sdl3.GetError())
    return false
  }


  return true
}

clay_process_event :: proc(event: ^sdl3.Event) {
  // NOTE(dendo): clay's Clay_SetPointerState expects to be updated only once per frame
  // Is it okay to call it here?

  #partial switch event.type {
  case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
    switch event.button.button {
    case 1:
      // left
      claystate.is_left_mouse_down = event.button.down
    case 2:
      // middle
    case 3:
      // right
    }
  case .MOUSE_MOTION:
    claystate.mouse_x = event.motion.x
    claystate.mouse_y = event.motion.y
  case .MOUSE_WHEEL:
    x := event.wheel.x * 16
    y := event.wheel.y * -16
    // TODO(dendo): delta time shouldn't be zero
    clay.UpdateScrollContainers(true, {x, y}, 0)
  }

  clay.SetPointerState(
      { claystate.mouse_x, claystate.mouse_y },
      claystate.is_left_mouse_down,
  )
}

// NOTE: copied and modified from https://github.com/nicbarker/clay/blob/main/renderers/SDL3/clay_renderer_SDL3.c

NUM_CIRCLE_SEGMENTS :: 16

clay_render_fill_rounded_rect :: proc(rect : sdl3.FRect, cornerRadius: f32, _color: clay.Color) {
  color: sdl3.FColor = { _color.r/255, _color.g/255, _color.b/255, _color.a/255 }

  indexCount, vertexCount : i32

  minRadius := min(rect.w, rect.h) / 2.0
  clampedRadius := min(cornerRadius, minRadius)

  numCircleSegments := max(NUM_CIRCLE_SEGMENTS, int(clampedRadius * 0.5))

  totalVertices := 4 + (4 * (numCircleSegments * 2)) + 2*4
  totalIndices := 6 + (4 * (numCircleSegments * 3)) + 6*4

  assert(totalVertices < 4096, "very big stack allocation")
  assert(totalIndices < 4096, "very big stack allocation")

  vertices_bytes := intrinsics.alloca((totalVertices) * size_of(sdl3.Vertex), size_of(sdl3.Vertex))
  vertices := ([^]sdl3.Vertex)(vertices_bytes)[:totalVertices]

  indices_bytes := intrinsics.alloca((totalIndices) * size_of(i32), size_of(i32))
  indices := ([^]i32)(indices_bytes)[:totalIndices]

  //define center rectangle
  vertices[vertexCount] = { {rect.x + clampedRadius, rect.y + clampedRadius}, color, {0, 0} } //0 center TL
  vertexCount += 1
  vertices[vertexCount] = { {rect.x + rect.w - clampedRadius, rect.y + clampedRadius}, color, {1, 0} } //1 center TR
  vertexCount += 1
  vertices[vertexCount] = { {rect.x + rect.w - clampedRadius, rect.y + rect.h - clampedRadius}, color, {1, 1} } //2 center BR
  vertexCount += 1
  vertices[vertexCount] = { {rect.x + clampedRadius, rect.y + rect.h - clampedRadius}, color, {0, 1} } //3 center BL
  vertexCount += 1

  indices[indexCount] = 0
  indexCount += 1
  indices[indexCount] = 1
  indexCount += 1
  indices[indexCount] = 3
  indexCount += 1
  indices[indexCount] = 1
  indexCount += 1
  indices[indexCount] = 2
  indexCount += 1
  indices[indexCount] = 3
  indexCount += 1

  //define rounded corners as triangle fans
  step := (math.PI/2) / f32(numCircleSegments)
  for i := 0; i < numCircleSegments; i += 1 {
    angle2 := f32(i) + 1.0 * step
    angle1 := f32(i) * step

    for j: i32 = 0; j < 4; j += 1 {  // Iterate over four corners
      cx, cy, signX, signY: f32

      switch (j) {
          case 0:
            cx = rect.x + clampedRadius
            cy = rect.y + clampedRadius
            signX = -1;
            signY = -1 // Top-left
          case 1:
            cx = rect.x + rect.w - clampedRadius
            cy = rect.y + clampedRadius
            signX = 1
            signY = -1 // Top-right
          case 2: 
            cx = rect.x + rect.w - clampedRadius
            cy = rect.y + rect.h - clampedRadius
            signX = 1
            signY = 1 // Bottom-right
          case 3:
            cx = rect.x + clampedRadius
            cy = rect.y + rect.h - clampedRadius
            signX = -1
            signY = 1 // Bottom-left
          case: return
      }

      vertices[vertexCount] = { {cx + sdl3.cosf(angle1) * clampedRadius * signX, cy + sdl3.sinf(angle1) * clampedRadius * signY}, color, {0, 0} }
      vertexCount += 1
      vertices[vertexCount] = { {cx + sdl3.cosf(angle2) * clampedRadius * signX, cy + sdl3.sinf(angle2) * clampedRadius * signY}, color, {0, 0} }
      vertexCount += 1

      indices[indexCount] = j  // Connect to corresponding central rectangle vertex
      indexCount += 1
      indices[indexCount] = vertexCount - 2
      indexCount += 1
      indices[indexCount] = vertexCount - 1
      indexCount += 1
    }
  }

  //Define edge rectangles
  // Top edge
  vertices[vertexCount] = { {rect.x + clampedRadius, rect.y}, color, {0, 0} } //TL
  vertexCount += 1
  vertices[vertexCount] = { {rect.x + rect.w - clampedRadius, rect.y}, color, {1, 0} } //TR
  vertexCount += 1

  indices[indexCount] = 0
  indexCount += 1
  indices[indexCount] = vertexCount - 2 //TL
  indexCount += 1
  indices[indexCount] = vertexCount - 1 //TR
  indexCount += 1
  indices[indexCount] = 1
  indexCount += 1
  indices[indexCount] = 0
  indexCount += 1
  indices[indexCount] = vertexCount - 1 //TR
  indexCount += 1
  // Right edge
  vertices[vertexCount] = { {rect.x + rect.w, rect.y + clampedRadius}, color, {1, 0} } //RT
  vertexCount += 1
  vertices[vertexCount] = { {rect.x + rect.w, rect.y + rect.h - clampedRadius}, color, {1, 1} } //RB
  vertexCount += 1

  indices[indexCount] = 1
  indexCount += 1
  indices[indexCount] = vertexCount - 2 //RT
  indexCount += 1
  indices[indexCount] = vertexCount - 1 //RB
  indexCount += 1
  indices[indexCount] = 2
  indexCount += 1
  indices[indexCount] = 1
  indexCount += 1
  indices[indexCount] = vertexCount - 1 //RB
  indexCount += 1
  // Bottom edge
  vertices[vertexCount] = { {rect.x + rect.w - clampedRadius, rect.y + rect.h}, color, {1, 1} } //BR
  vertexCount += 1
  vertices[vertexCount] = { {rect.x + clampedRadius, rect.y + rect.h}, color, {0, 1} } //BL
  vertexCount += 1

  indices[indexCount] = 2
  indexCount += 1
  indices[indexCount] = vertexCount - 2 //BR
  indexCount += 1
  indices[indexCount] = vertexCount - 1 //BL
  indexCount += 1
  indices[indexCount] = 3
  indexCount += 1
  indices[indexCount] = 2
  indexCount += 1
  indices[indexCount] = vertexCount - 1 //BL
  indexCount += 1
  // Left edge
  vertices[vertexCount] = { {rect.x, rect.y + rect.h - clampedRadius}, color, {0, 1} } //LB
  vertexCount += 1
  vertices[vertexCount] = { {rect.x, rect.y + clampedRadius}, color, {0, 0} } //LT
  vertexCount += 1

  indices[indexCount] = 3
  indexCount += 1
  indices[indexCount] = vertexCount - 2 //LB
  indexCount += 1
  indices[indexCount] = vertexCount - 1 //LT
  indexCount += 1
  indices[indexCount] = 0
  indexCount += 1
  indices[indexCount] = 3
  indexCount += 1
  indices[indexCount] = vertexCount - 1 //LT
  indexCount += 1

  // Render everything
  sdl3.RenderGeometry(platstate.renderer, nil, raw_data(vertices), vertexCount, raw_data(indices), indexCount)
}

clay_render_arc :: proc (center: sdl3.FPoint, radius, start_angle, end_angle, thickness : f32, color: clay.Color) {
  sdl3.SetRenderDrawColor(platstate.renderer, u8(color.r), u8(color.g), u8(color.b), u8(color.a))

  rad_start := start_angle * (math.PI / 180.0)
  rad_end := end_angle * (math.PI / 180.0)

  num_circle_segments := max(NUM_CIRCLE_SEGMENTS, int(radius * 1.5)) //increase circle segments for larger circles, 1.5 is arbitrary.
  assert(num_circle_segments <= 4096, "big circles, very big stack allocation")

  angle_step := (rad_end - rad_start) / f32(num_circle_segments)
  thickness_step: f32 = 0.4 //arbitrary value to avoid overlapping lines. Changing THICKNESS_STEP or numCircleSegments might cause artifacts.

  bytes := intrinsics.alloca((num_circle_segments+1) * size_of(sdl3.FRect), size_of(sdl3.FRect))
  points := ([^]sdl3.FPoint)(bytes)[:num_circle_segments + 1]

  for t := thickness_step; t < thickness - thickness_step; t += thickness_step {
    clamped_radius := max(radius - t, 1.0)

    for i := 0; i <= num_circle_segments; i += 1 {
      angle := rad_start + f32(i) * angle_step
      points[i] = {
        sdl3.roundf(center.x + sdl3.cosf(angle) * clamped_radius),
        sdl3.roundf(center.y + sdl3.sinf(angle) * clamped_radius)
      }
    }
    sdl3.RenderLines(platstate.renderer, raw_data(points[:]), i32(num_circle_segments + 1));
  }
}

clay_render :: proc(appstate: ^nbtfinder.AppState) {
  renderer := platstate.renderer

  images: ui.Clay_Images = {
    profile = claystate.image
  }
  render_commands := ui.clay_draw_commands(appstate, images)

  for i in 0..<i32(render_commands.length) {
      rcmd := clay.RenderCommandArray_Get(&render_commands, i)
      bounding_box : clay.BoundingBox = rcmd.boundingBox
      rect : sdl3.FRect = { bounding_box.x, bounding_box.y, bounding_box.width, bounding_box.height }

      #partial switch rcmd.commandType {
      case .None:
      case .Rectangle:
        rectangle := rcmd.renderData.rectangle
        color := rectangle.backgroundColor

        sdl3.SetRenderDrawColor(renderer, u8(color[0]), u8(color[1]), u8(color[2]), u8(color[3]))

        if rectangle.cornerRadius.topLeft > 0 {
          clay_render_fill_rounded_rect(rect, rectangle.cornerRadius.topLeft, color)
        } else {
          sdl3.RenderFillRect(renderer, &rect)
        }
      case .Border:
        border := rcmd.renderData.border

        minRadius := min(rect.w, rect.h) / 2.0
        clampedRadii : clay.CornerRadius = {
          topLeft = min(border.cornerRadius.topLeft, minRadius),
          topRight = min(border.cornerRadius.topRight, minRadius),
          bottomLeft = min(border.cornerRadius.bottomLeft, minRadius),
          bottomRight = min(border.cornerRadius.bottomRight, minRadius)
        };
        //edges
        sdl3.SetRenderDrawColor(platstate.renderer, u8(border.color.r), u8(border.color.g), u8(border.color.b), u8(border.color.a))
        if (border.width.left > 0) {
          starting_y := rect.y + clampedRadii.topLeft
          length := rect.h - clampedRadii.topLeft - clampedRadii.bottomLeft
          line : sdl3.FRect= { rect.x - 1, starting_y, f32(border.width.left), length }
          sdl3.RenderFillRect(platstate.renderer, &line)
        }
        if (border.width.right > 0) {
          starting_x := rect.x + rect.w - f32(border.width.right) + 1
          starting_y := rect.y + clampedRadii.topRight
          length := rect.h - clampedRadii.topRight - clampedRadii.bottomRight
          line : sdl3.FRect = { starting_x, starting_y, f32(border.width.right), length };
          sdl3.RenderFillRect(platstate.renderer, &line)
        }
        if (border.width.top > 0) {
          starting_x := rect.x + clampedRadii.topLeft
          length := rect.w - clampedRadii.topLeft - clampedRadii.topRight
          line : sdl3.FRect = { starting_x, rect.y - 1, length, f32(border.width.top) }
          sdl3.RenderFillRect(platstate.renderer, &line)
        }
        if (border.width.bottom > 0) {
          starting_x := rect.x + clampedRadii.bottomLeft
          starting_y := rect.y + rect.h - f32(border.width.bottom) + 1
          length := rect.w - clampedRadii.bottomLeft - clampedRadii.bottomRight
          line : sdl3.FRect = { starting_x, starting_y, length, f32(border.width.bottom) }
          sdl3.RenderFillRect(platstate.renderer, &line)
        }
        //corners
        if (border.cornerRadius.topLeft > 0) {
          centerX := rect.x + clampedRadii.topLeft -1
          centerY := rect.y + clampedRadii.topLeft - 1
          clay_render_arc({centerX, centerY}, clampedRadii.topLeft,
                180.0, 270.0, f32(border.width.top), border.color)
        }
        if (border.cornerRadius.topRight > 0) {
          centerX := rect.x + rect.w - clampedRadii.topRight
          centerY := rect.y + clampedRadii.topRight - 1
          clay_render_arc({centerX, centerY}, clampedRadii.topRight,
              270.0, 360.0, f32(border.width.top), border.color)
        }
        if (border.cornerRadius.bottomLeft > 0) {
          centerX := rect.x + clampedRadii.bottomLeft -1
          centerY := rect.y + rect.h - clampedRadii.bottomLeft
          clay_render_arc({centerX, centerY}, clampedRadii.bottomLeft,
              90.0, 180.0, f32(border.width.bottom), border.color)
        }
        if (border.cornerRadius.bottomRight > 0) {
          centerX := rect.x + rect.w - clampedRadii.bottomRight
          centerY := rect.y + rect.h - clampedRadii.bottomRight
          clay_render_arc({centerX, centerY}, clampedRadii.bottomRight,
              0.0, 90.0, f32(border.width.bottom), border.color)
        }

      case .Text:
        config := &rcmd.renderData.text

        font := claystate.fonts[config.fontId]
        ttf.SetFontSize(font, f32(config.fontSize))

        // TODO: is config.stringContents.chars always null terminated?
        text := ttf.CreateText(platstate.text_engine, font, cstring(config.stringContents.chars), uint(config.stringContents.length))
        assert(text != nil)

        ttf.SetTextColor(text, u8(config.textColor.r), u8(config.textColor.g), u8(config.textColor.b), u8(config.textColor.a))
        ttf.DrawRendererText(text, rect.x, rect.y)
        ttf.DestroyText(text)
      case .Image:
        texture := (^sdl3.Texture)(rcmd.renderData.image.imageData)
        sdl3.RenderTexture(platstate.renderer, texture, nil, &rect)
      case .ScissorStart:
        boundingBox := rcmd.boundingBox
        currentClippingRectangle : sdl3.Rect = {
          x = i32(boundingBox.x),
          y = i32(boundingBox.y),
          w = i32(boundingBox.width),
          h = i32(boundingBox.height),
        }
        sdl3.SetRenderClipRect(platstate.renderer, &currentClippingRectangle)

      case .ScissorEnd:
        sdl3.SetRenderClipRect(platstate.renderer, nil)

      case:
        assert(false, "Clay render command not implemented")
      }
  }

	sdl3.RenderPresent(platstate.renderer)
}

clay_fini :: proc() {
  sdl3.DestroyTexture(claystate.image)

  for i := 0; i < 4; i += 1 {
    ttf.CloseFont(claystate.fonts[i])
  }
}

