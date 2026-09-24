package ui
// NOTE(dendo): not sure how to proprly architecture the UI, shouldn't be skiping handmade lessons

import "core:fmt"
import "../"
import mu "vendor:microui"


draw_tag :: proc(ctx: ^mu.Context, appstate : ^nbtfinder.AppState, tag : ^nbtfinder.NBT_Tag) {

  name := nbtfinder.nbt_string_get(&tag.name, appstate.header)

  switch tag.type {
    case .End:
      assert(false)

    case .Byte:
      s := fmt.tprintf("%v: i8 = %v", name, tag.value.byte)
      mu.label(ctx, s)

    case .Short:
      s := fmt.tprintf("%v: i16 = %v", name, tag.value.short)
      mu.label(ctx, s)

    case .Int:
      s := fmt.tprintf("%v: i32 = %v", name, tag.value.integer)
      mu.label(ctx, s)

    case .Long:
      s := fmt.tprintf("%v: i64 = %v", name, tag.value.long)
      mu.label(ctx, s)

    case .Float:
      s := fmt.tprintf("%v: f32 = %v", name, tag.value.float)
      mu.label(ctx, s)

    case .Double:
      s := fmt.tprintf("%v: f64 = %v", name, tag.value.double)
      mu.label(ctx, s)

    case .ByteArray:
      s := fmt.tprintf("%v: [%v]i8", name, tag.value.byte_array.count)
      mu.label(ctx, s)

    case .String:
      s := fmt.tprintf("%v: string = \"%v\"", name, tag.value.str)
      mu.label(ctx, s)

    case .List:
      start_index := tag.value.list.start_index
      count := tag.value.list.count

      assert(count >= 0)
      s := fmt.tprint(name, len(name) != 0 ? ": " : "", count, " items", sep = "")
      if .ACTIVE in mu.treenode(ctx, s) {
        for i : i32 = 0; i < count; i += 1 {
          tag := appstate.header.tags[start_index + u32(i)]

          mu.push_id_rawptr(ctx, &i, size_of(i))
          draw_tag(ctx, appstate, &tag)
          mu.pop_id(ctx)
        }
      }

    case .Compound:
      start_index := tag.value.compound.start_index
      count := tag.value.compound.count

      assert(count >= 0)
      s := fmt.tprint(name, len(name) != 0 ? ": " : "", count, " tags", sep = "")
      if .ACTIVE in mu.treenode(ctx, s, opt = { } ) {
        for i : i32 = 0; i < count; i += 1 {
          tag := appstate.header.tags[start_index + u32(i)]

          mu.push_id_rawptr(ctx, &i, size_of(i))
          draw_tag(ctx, appstate, &tag)
          mu.pop_id(ctx)
        }
      }

    case .IntArray:
      s := fmt.tprintf("%v: [%v]i32", name, tag.value.int_array.count)
      mu.label(ctx, s)

    case .LongArray:
      s := fmt.tprintf("%v: [%v]i32", name, tag.value.long_array.count)
      mu.label(ctx, s)

    case:
      assert(false)
  }
}

draw_nbt_header :: proc(ctx: ^mu.Context, appstate : ^nbtfinder.AppState, header : ^nbtfinder.NBT_Decoded_Header) {
  root_tag := header.tags[header.root_tag_index]

  draw_tag(ctx, appstate, &root_tag)
}

microui_draw_commands :: proc(ctx: ^mu.Context, appstate : ^nbtfinder.AppState, rect : mu.Rect) {
  mu.begin(ctx)
  {
    if mu.begin_window(ctx, nbtfinder.window_specs.title, rect, { .NO_CLOSE, .NO_RESIZE }) {
      win := mu.get_current_container(ctx);
      win.rect.w = rect.w;
      win.rect.h = rect.h;

      /*
      if .SUBMIT in mu.button(ctx, "test") {
        fmt.println("Button Press")
      }
      */

      draw_nbt_header(ctx, appstate, appstate.header)

      mu.end_window(ctx)
    }
  }
  mu.end(ctx)
}


