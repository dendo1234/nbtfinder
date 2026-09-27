package platform_sdl3

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:strings"
import "base:runtime"
import "vendor:sdl3"
import "vendor:sdl3/ttf"
import "vendor:sdl3/image"
import clay "clay:clay-odin"

import "../nbtfinder"
import "../nbtfinder/ui"

COLOR_RANGE :: 255 // divisor to apply to the clay.Color values. 255 means values are 0 - 255
NUM_CIRCLE_SEGMENTS :: 12 // resolution of circles

SDL3_Clay_State :: struct {
  is_left_mouse_down: bool,
  mouse_x: f32,
  mouse_y: f32,
  wheel_x: f32,
  wheel_y: f32,

  fonts: [4]^ttf.Font,

  last_update_time: u64,
  debug_mode: bool,


  claystate: ui.Clay_State,
}


sdl3_clay_state : SDL3_Clay_State

clay_load_assets :: proc() -> bool {
  // DESC: Load images

  BYTE_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_byte.png")
  SHORT_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_short.png")
  INT_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_int.png")
  LONG_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_long.png")
  FLOAT_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_float.png")
  DOUBLE_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_double.png")
  BYTE_ARRAY_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_byte-array.png")
  STRING_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_string.png")
  LIST_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_list.png")
  COMPOUND_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_compound.png")
  INT_ARRAY_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_int-array.png")
  LONG_ARRAY_TAG_BYTES :: #load("../../data/nbt icons/NbtSprite_long-array.png")

  ICONS : [13][]u8 : {
    BYTE_TAG_BYTES, // TODO: this is a place holder
    BYTE_TAG_BYTES,
    SHORT_TAG_BYTES,
    INT_TAG_BYTES,
    LONG_TAG_BYTES,
    FLOAT_TAG_BYTES,
    DOUBLE_TAG_BYTES,
    BYTE_ARRAY_TAG_BYTES,
    STRING_TAG_BYTES,
    LIST_TAG_BYTES,
    COMPOUND_TAG_BYTES,
    INT_ARRAY_TAG_BYTES,
    LONG_ARRAY_TAG_BYTES
  }

  for bytes, index in ICONS {
    stream := sdl3.IOFromMem(raw_data(bytes), len(bytes))
    assert(stream != nil)

    sdl3_clay_state.claystate.images.raw[index] = image.LoadTextureTyped_IO(platstate.renderer, stream, true, "PNG")
    assert(sdl3_clay_state.claystate.images.raw[index] != nil)
  }


  // NOTE(dendo): I found it pretty weird that the executable size grew way more than the 977 KiB of the dejavu file.
  // As it turns out, this fenomenom only happens in debug builds. So it isn't that intersing.
  // It's probraly the sdl3.IOFromMem call that is causing it
  DEJA_VU_SANS_BYTES :: #load("../../data/DejaVuSans.ttf")

  dejavu_stream := sdl3.IOFromMem(raw_data(DEJA_VU_SANS_BYTES), len(DEJA_VU_SANS_BYTES))
  assert(dejavu_stream != nil)
  sdl3_clay_state.fonts[0] = ttf.OpenFontIO(dejavu_stream, true, 12)
  if (sdl3_clay_state.fonts[0] == nil) {
    fmt.eprintfln("Failed to create Font: %v", sdl3.GetError())
    return false
  }

  return true
}

// DESC: RENDERER(independent of nbtfinder):
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
  clay.Initialize(arena, { f32(nbtfinder.window_specs.width), f32(nbtfinder.window_specs.height) }, { handler = error_handler })

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
    // wrapMode:      TextWrapMode,
    // textAlignment: TextAlignment,

    font := sdl3_clay_state.fonts[config.fontId]
    ttf.SetFontSize(font, f32(config.fontSize))

    // ttf.SetLineSkip(font, i32(config.lineHeight))
    // ttf.SetFontWrapAlignment(font, )

    width, height: i32
    ttf.GetStringSize(font, cstring(text.chars), uint(text.length), &width, &height);

    return {
      width = f32(width),
      height = f32(height)
    }
  }

  // Tell clay how to measure text
  clay.SetMeasureTextFunction(measure_text, nil)

  if (!clay_load_assets()) {
    return false
  }

  sdl3_clay_state.last_update_time = sdl3.GetTicksNS()

  return true
}

clay_process_event :: proc(event: ^sdl3.Event) {
  #partial switch event.type {
  case .KEY_DOWN:
    key := event.key
    if key.key == sdl3.K_F11 {
      sdl3_clay_state.debug_mode = !sdl3_clay_state.debug_mode
      clay.SetDebugModeEnabled(sdl3_clay_state.debug_mode)
    }

  case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
    switch event.button.button {
    case 1:
      // left
      sdl3_clay_state.is_left_mouse_down = event.button.down
    case 2:
      // middle
    case 3:
      // right
    }
  case .MOUSE_MOTION:
    sdl3_clay_state.mouse_x = event.motion.x
    sdl3_clay_state.mouse_y = event.motion.y
  case .MOUSE_WHEEL:
    sdl3_clay_state.wheel_x += event.wheel.x
    sdl3_clay_state.wheel_y += event.wheel.y
  case .WINDOW_RESIZED:
    w := event.window.data1
    h := event.window.data2
    clay.SetLayoutDimensions({width = f32(w), height = f32(h)})
  }
}

alpha_blend :: proc(background, foreground : sdl3.FColor) -> sdl3.FColor {
  ret: sdl3.FColor

  // A
  ret[3] = foreground[3] + background[3]*(1 - foreground[3])

  // RGB
  ret[0] = (foreground[0]*foreground[3] + background[0]*background[3]*(1 - foreground[3]))/ret[3]
  ret[1] = (foreground[1]*foreground[3] + background[1]*background[3]*(1 - foreground[3]))/ret[3]
  ret[2] = (foreground[2]*foreground[3] + background[2]*background[3]*(1 - foreground[3]))/ret[3]

  return ret
}

// NOTE: copied and modified from https://github.com/nicbarker/clay/blob/main/renderers/SDL3/clay_renderer_SDL3.c

draw_rectangle_rounded :: proc(rect : sdl3.FRect, cornerRadius: f32, color: sdl3.FColor) {
  // WC = worst case
  // NOTE(dendo): not sure about this. Should VLA be used or just allocate the worst case every time?
  // probraly wont make a difference anyway
  WC_VERTICIES_COUNT :: 4 + (4 * (NUM_CIRCLE_SEGMENTS * 2)) + 2*4
  WC_INDICIES_COUNT :: 6 + (4 * (NUM_CIRCLE_SEGMENTS * 3)) + 6*4
  #assert(WC_VERTICIES_COUNT*size_of(sdl3.Vertex) < 4096, "very big stack allocation")
  #assert(WC_INDICIES_COUNT*size_of(i32) < 4096, "very big stack allocation")

  indexCount, vertexCount : i32 = {}, {}
  maxRadius := min(rect.w, rect.h) / 2.0
  clampedRadius := min(cornerRadius, maxRadius)

  // numCircleSegments per corner
  numCircleSegments := min(NUM_CIRCLE_SEGMENTS, int(clampedRadius * 0.5))

  totalVertices := 4 + (4 * (numCircleSegments * 2)) + 2*4
  totalIndices := 6 + (4 * (numCircleSegments * 3)) + 6*4

  vertices: [WC_VERTICIES_COUNT]sdl3.Vertex
  indices: [WC_INDICIES_COUNT]i32

  //define center rectangle
  vertices[vertexCount + 0] = { {rect.x + clampedRadius, rect.y + clampedRadius}, color, {0, 0} } //0 center TL
  vertices[vertexCount + 1] = { {rect.x + rect.w - clampedRadius, rect.y + clampedRadius}, color, {1, 0} } //1 center TR
  vertices[vertexCount + 2] = { {rect.x + rect.w - clampedRadius, rect.y + rect.h - clampedRadius}, color, {1, 1} } //2 center BR
  vertices[vertexCount + 3] = { {rect.x + clampedRadius, rect.y + rect.h - clampedRadius}, color, {0, 1} } //3 center BL
  vertexCount += 4

  indices[indexCount + 0] = 0
  indices[indexCount + 1] = 1
  indices[indexCount + 2] = 3
  indices[indexCount + 3] = 1
  indices[indexCount + 4] = 2
  indices[indexCount + 5] = 3
  indexCount += 6

  //define rounded corners as triangle fans
  step := (math.PI/2) / f32(numCircleSegments)
  for i := 0; i < numCircleSegments; i += 1 {
    angle1 := f32(i) * step
    angle2 := f32(i + 1) * step

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

      vertices[vertexCount + 0] = { {cx + sdl3.cosf(angle1) * clampedRadius * signX, cy + sdl3.sinf(angle1) * clampedRadius * signY}, color, {0, 0} }
      vertices[vertexCount + 1] = { {cx + sdl3.cosf(angle2) * clampedRadius * signX, cy + sdl3.sinf(angle2) * clampedRadius * signY}, color, {0, 0} }
      vertexCount += 2

      indices[indexCount + 0] = j  // Connect to corresponding central rectangle vertex
      indices[indexCount + 1] = vertexCount - 2
      indices[indexCount + 2] = vertexCount - 1
      indexCount += 3
    }
  }

  //Define edge rectangles
  // Top edge
  vertices[vertexCount + 0] = { {rect.x + clampedRadius, rect.y}, color, {0, 0} } //TL
  vertices[vertexCount + 1] = { {rect.x + rect.w - clampedRadius, rect.y}, color, {1, 0} } //TR
  vertexCount += 2

  indices[indexCount + 0] = 0
  indices[indexCount + 1] = vertexCount - 2 //TL
  indices[indexCount + 2] = vertexCount - 1 //TR
  indices[indexCount + 3] = 1
  indices[indexCount + 4] = 0
  indices[indexCount + 5] = vertexCount - 1 //TR
  indexCount += 6
  // Right edge
  vertices[vertexCount + 0] = { {rect.x + rect.w, rect.y + clampedRadius}, color, {1, 0} } //RT
  vertices[vertexCount + 1] = { {rect.x + rect.w, rect.y + rect.h - clampedRadius}, color, {1, 1} } //RB
  vertexCount += 2

  indices[indexCount + 0] = 1
  indices[indexCount + 1] = vertexCount - 2 //RT
  indices[indexCount + 2] = vertexCount - 1 //RB
  indices[indexCount + 3] = 2
  indices[indexCount + 4] = 1
  indices[indexCount + 5] = vertexCount - 1 //RB
  indexCount += 6
  // Bottom edge
  vertices[vertexCount + 0] = { {rect.x + rect.w - clampedRadius, rect.y + rect.h}, color, {1, 1} } //BR
  vertices[vertexCount + 1] = { {rect.x + clampedRadius, rect.y + rect.h}, color, {0, 1} } //BL
  vertexCount += 2

  indices[indexCount + 0] = 2
  indices[indexCount + 1] = vertexCount - 2 //BR
  indices[indexCount + 2] = vertexCount - 1 //BL
  indices[indexCount + 3] = 3
  indices[indexCount + 4] = 2
  indices[indexCount + 5] = vertexCount - 1 //BL
  indexCount += 6
  // Left edge
  vertices[vertexCount + 0] = { {rect.x, rect.y + rect.h - clampedRadius}, color, {0, 1} } //LB
  vertices[vertexCount + 1] = { {rect.x, rect.y + clampedRadius}, color, {0, 0} } //LT
  vertexCount += 2

  indices[indexCount + 0] = 3
  indices[indexCount + 1] = vertexCount - 2 //LB
  indices[indexCount + 2] = vertexCount - 1 //LT
  indices[indexCount + 3] = 0
  indices[indexCount + 4] = 3
  indices[indexCount + 5] = vertexCount - 1 //LT
  indexCount += 6

  // Render everything
  sdl3.RenderGeometry(platstate.renderer, nil, raw_data(vertices[:]), vertexCount, raw_data(indices[:]), indexCount)
}

draw_arc :: proc (center: sdl3.FPoint, radius, start_angle, end_angle, thickness : f32, color: sdl3.FColor) {
  // WC = worst case
  // NOTE(dendo): not sure about this. Should VLA be used or just allocate the worst case every time?
  // probraly wont make a difference anyway
  WC_VERTICIES_COUNT :: 2 + (NUM_CIRCLE_SEGMENTS * 2)
  WC_INDICIES_COUNT :: 3 * (NUM_CIRCLE_SEGMENTS * 2)
  #assert(WC_VERTICIES_COUNT*size_of(sdl3.Vertex) < 4096, "very big stack allocation")
  #assert(WC_INDICIES_COUNT*size_of(i32) < 4096, "very big stack allocation")

  rad_start := start_angle * (math.PI / 180.0)
  rad_end := end_angle * (math.PI / 180.0)

  assert(radius >= 0)
  num_circle_segments := min(NUM_CIRCLE_SEGMENTS, i32(radius * 1.5)) //increase circle segments for larger circles, 1.5 is arbitrary.
  if (num_circle_segments == 0) {
    return
  }

  totalVertices := 2 + (num_circle_segments * 2)
  totalIndices := 3 * (num_circle_segments * 2)

  vertices: [WC_VERTICIES_COUNT]sdl3.Vertex
  indices: [WC_INDICIES_COUNT]i32

  indexCount, vertexCount : i32 = {}, {}

  arc_size := rad_end - rad_start

  angle_step := arc_size/f32(num_circle_segments)
  outer_radius := radius
  inner_radius := radius - thickness

  vertices[0] = { {center.x + sdl3.cosf(rad_start)*outer_radius, center.y + sdl3.sinf(rad_start)*outer_radius }, color, {0, 0}};
  vertices[1] = { {center.x + sdl3.cosf(rad_start)*inner_radius, center.y + sdl3.sinf(rad_start)*inner_radius }, color, {0, 0}};
  vertexCount += 2

  for seg_index: i32 = 0; seg_index < num_circle_segments; seg_index += 1 {
    // angle = rad_start + 0*angle_step is alreadly computed
    angle := rad_start + f32(seg_index+1)*angle_step

    //vertices[2*seg_index + 0]
    //vertices[2*seg_index + 1] are alreadly computed
    vertices[2*seg_index + 2] = { {center.x + sdl3.cosf(angle)*outer_radius, center.y + sdl3.sinf(angle)*outer_radius }, color, {0, 0}};
    vertices[2*seg_index + 3] = { {center.x + sdl3.cosf(angle)*inner_radius, center.y + sdl3.sinf(angle)*inner_radius }, color, {0, 0}};

    indices[6*seg_index + 0] = (2*seg_index) + 0
    indices[6*seg_index + 1] = (2*seg_index) + 1
    indices[6*seg_index + 2] = (2*seg_index) + 2

    indices[6*seg_index + 3] = (2*seg_index) + 1
    indices[6*seg_index + 4] = (2*seg_index) + 2
    indices[6*seg_index + 5] = (2*seg_index) + 3

    vertexCount += 2
    indexCount += 6
  }

  sdl3.RenderGeometry(platstate.renderer, nil, raw_data(vertices[:]), vertexCount, raw_data(indices[:]), indexCount)
}

draw_border :: proc(rect : sdl3.FRect, cornerRadius: clay.CornerRadius, width: clay.BorderWidth, color: sdl3.FColor) {
  WC_VERTICIES_COUNT :: 4 + (4 * (NUM_CIRCLE_SEGMENTS * 2)) + 2*4
  WC_INDICIES_COUNT :: 6 + (4 * (NUM_CIRCLE_SEGMENTS * 3)) + 6*4
  #assert(WC_VERTICIES_COUNT*size_of(sdl3.Vertex) < 4096, "very big stack allocation")
  #assert(WC_INDICIES_COUNT*size_of(i32) < 4096, "very big stack allocation")
  
  indexCount, vertexCount : i32 = {}, {}

  maxRadius := min(rect.w, rect.h) / 2.0
  clampedRadii : clay.CornerRadius = {
    topLeft = min(cornerRadius.topLeft, maxRadius),
    topRight = min(cornerRadius.topRight, maxRadius),
    bottomLeft = min(cornerRadius.bottomLeft, maxRadius),
    bottomRight = min(cornerRadius.bottomRight, maxRadius)
  };

  // edges
  {
    rects: [4]sdl3.FRect
    rect_count: i32 = 0

    if (width.left > 0) {
      starting_y := rect.y + clampedRadii.topLeft
      length := rect.h - clampedRadii.topLeft - clampedRadii.bottomLeft
      rects[rect_count] = { rect.x, starting_y, f32(width.left), length }
      rect_count += 1

    }
    if (width.right > 0) {
      starting_x := rect.x + rect.w - f32(width.right)
      starting_y := rect.y + clampedRadii.topRight
      length := rect.h - clampedRadii.topRight - clampedRadii.bottomRight
      rects[rect_count] = { starting_x, starting_y, f32(width.right), length };
      rect_count += 1
    }
    if (width.top > 0) {
      starting_x := rect.x + clampedRadii.topLeft
      length := rect.w - clampedRadii.topLeft - clampedRadii.topRight
      rects[rect_count] = { starting_x, rect.y, length, f32(width.top) }
      rect_count += 1
    }
    if (width.bottom > 0) {
      starting_x := rect.x + clampedRadii.bottomLeft
      starting_y := rect.y + rect.h - f32(width.bottom)
      length := rect.w - clampedRadii.bottomLeft - clampedRadii.bottomRight
      rects[rect_count] = { starting_x, starting_y, length, f32(width.bottom) }
      rect_count += 1
    }

    sdl3.RenderFillRects(platstate.renderer, raw_data(rects[:]), rect_count)
  }

  // corners
  {
    // NOTE(dendo): this 4 calls are doing basicaly the same thing (if the clampedRadii is the same),
    // the only difference (in relative coordinates) is the sign of the X and Y coordinates on the vertices.
    // maybe there is some optimazation potencial here
    if (cornerRadius.topLeft > 0) {
      centerX := rect.x + clampedRadii.topLeft
      centerY := rect.y + clampedRadii.topLeft
      draw_arc({centerX, centerY}, clampedRadii.topLeft,
            180.0, 270.0, f32(width.top), color)
    }
    if (cornerRadius.topRight > 0) {
      centerX := rect.x + rect.w - clampedRadii.topRight
      centerY := rect.y + clampedRadii.topRight
      draw_arc({centerX, centerY}, clampedRadii.topRight,
          270.0, 360.0, f32(width.top), color)
    }
    if (cornerRadius.bottomLeft > 0) {
      centerX := rect.x + clampedRadii.bottomLeft
      centerY := rect.y + rect.h - clampedRadii.bottomLeft
      draw_arc({centerX, centerY}, clampedRadii.bottomLeft,
          90.0, 180.0, f32(width.bottom), color)
    }
    if (cornerRadius.bottomRight > 0) {
      centerX := rect.x + rect.w - clampedRadii.bottomRight
      centerY := rect.y + rect.h - clampedRadii.bottomRight
      draw_arc({centerX, centerY}, clampedRadii.bottomRight,
          0.0, 90.0, f32(width.bottom), color)
    }
  }
}


clay_render_draw_commands :: proc(renderer: ^sdl3.Renderer, render_commands: ^clay.ClayArray(clay.RenderCommand)) {
  sdl3.SetRenderDrawBlendMode(platstate.renderer, { .BLEND })

  is_color_blending: bool = false
	overlay_colors := make([dynamic]sdl3.FColor, context.temp_allocator)

  for i in 0..<i32(render_commands.length) {
      rcmd := clay.RenderCommandArray_Get(render_commands, i)
      bounding_box : clay.BoundingBox = rcmd.boundingBox
      rect : sdl3.FRect = { bounding_box.x, bounding_box.y, bounding_box.width, bounding_box.height }

      #partial switch rcmd.commandType {
      case .None:
      case .Rectangle:
        rectangle := rcmd.renderData.rectangle
        cc := rectangle.backgroundColor
        color: sdl3.FColor = { cc[0]/COLOR_RANGE, cc[1]/COLOR_RANGE, cc[2]/COLOR_RANGE, cc[3]/COLOR_RANGE }

        if is_color_blending {
          overlay := overlay_colors[len(overlay_colors) - 1 ]
          color = alpha_blend(color, overlay)
        }
        sdl3.SetRenderDrawColorFloat(renderer, color[0], color[1], color[2], color[3])

        if rectangle.cornerRadius.topLeft > 0 {
          draw_rectangle_rounded(rect, rectangle.cornerRadius.topLeft, color)
        } else {
          sdl3.RenderFillRect(renderer, &rect)
        }
      case .Border:
        border := rcmd.renderData.border

        cc := border.color
        color: sdl3.FColor = { cc[0]/COLOR_RANGE, cc[1]/COLOR_RANGE, cc[2]/COLOR_RANGE, cc[3]/COLOR_RANGE }

        if is_color_blending {
          overlay := overlay_colors[len(overlay_colors) - 1 ]
          color = alpha_blend(color, overlay)
        }
        sdl3.SetRenderDrawColorFloat(renderer, color[0], color[1], color[2], color[3])

        draw_border(rect, border.cornerRadius, border.width, color)

      case .Text:
        config := &rcmd.renderData.text

        font := sdl3_clay_state.fonts[config.fontId]
        ttf.SetFontSize(font, f32(config.fontSize))

        cc := config.textColor
        color: sdl3.FColor = { cc[0]/COLOR_RANGE, cc[1]/COLOR_RANGE, cc[2]/COLOR_RANGE, cc[3]/COLOR_RANGE }
        if is_color_blending {
          overlay := overlay_colors[len(overlay_colors) - 1 ]
          color = alpha_blend(color, overlay)
        }

        text := ttf.CreateText(platstate.text_engine, font, cstring(config.stringContents.chars), uint(config.stringContents.length))
        assert(text != nil)

        ttf.SetTextColorFloat(text, color[0], color[1], color[2], color[3])
        ttf.DrawRendererText(text, rect.x, rect.y)
        ttf.DestroyText(text)
      case .Image:
        texture := (^sdl3.Texture)(rcmd.renderData.image.imageData)
        sdl3.RenderTexture(platstate.renderer, texture, nil, &rect)
        if is_color_blending {
          // TODO: this is probraly wrong way to do overlay
          overlay := overlay_colors[len(overlay_colors) - 1]
          sdl3.SetRenderDrawColorFloat(platstate.renderer, overlay[0], overlay[1], overlay[2], overlay[3])
          sdl3.RenderFillRect(renderer, &rect)
        }
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

      case .OverlayColorStart:
        clay_color := rcmd.renderData.overlayColor.color
        overlay: sdl3.FColor = {
          clay_color[0]/COLOR_RANGE,
          clay_color[1]/COLOR_RANGE,
          clay_color[2]/COLOR_RANGE,
          clay_color[3]/COLOR_RANGE
        }
        append(&overlay_colors, overlay)
        is_color_blending = true

      case .OverlayColorEnd:
        pop(&overlay_colors)
        is_color_blending = false

      case:
        assert(false, "Clay render command not implemented")
      }
  }
}

clay_render :: proc(appstate: ^nbtfinder.AppState) {
  renderer := platstate.renderer

  temp_time := sdl3.GetTicksNS()
  delta_time := temp_time - sdl3_clay_state.last_update_time
  sdl3_clay_state.last_update_time = temp_time
  fdelta: f32 = f32(delta_time)/1e9

  clay.SetPointerState(
      { sdl3_clay_state.mouse_x, sdl3_clay_state.mouse_y },
      sdl3_clay_state.is_left_mouse_down,
  )
  clay.UpdateScrollContainers(!ui.clay_is_scrolling(sdl3_clay_state.claystate), {sdl3_clay_state.wheel_x, sdl3_clay_state.wheel_y}, fdelta)
  sdl3_clay_state.wheel_x = 0
  sdl3_clay_state.wheel_y = 0

  render_commands := ui.clay_draw_commands(appstate, &sdl3_clay_state.claystate, fdelta)

  clay_render_draw_commands(platstate.renderer, &render_commands)
	sdl3.RenderPresent(platstate.renderer)
}

clay_fini :: proc() {

  for i := 0; i < len(sdl3_clay_state.claystate.images.raw); i += 1 {
    sdl3.DestroyTexture((^sdl3.Texture)(sdl3_clay_state.claystate.images.raw[i]))
  }

  for i := 0; i < 4; i += 1 {
    ttf.CloseFont(sdl3_clay_state.fonts[i])
  }
}

