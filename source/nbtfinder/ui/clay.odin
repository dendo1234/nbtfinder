package ui
// NOTE(dendo): not sure how to proprly architecture the UI, shouldn't be skiping handmade lessons

import "../"
import "core:fmt"
import clay "clay:clay-odin"


/*
draw_tag :: proc(ctx: ^mu.Context, appstate : ^nbtfinder.AppState, tag : nbtfinder.NBT_Tag) {
  switch tag.type {
    case .End:
      assert(false)

    case .Byte:
      s := fmt.tprintf("%v: i8 = %v", tag.name, tag.value.byte)
      mu.label(ctx, s)

    case .Short:
      s := fmt.tprintf("%v: i16 = %v", tag.name, tag.value.short)
      mu.label(ctx, s)

    case .Int:
      s := fmt.tprintf("%v: i32 = %v", tag.name, tag.value.integer)
      mu.label(ctx, s)

    case .Long:
      s := fmt.tprintf("%v: i64 = %v", tag.name, tag.value.long)
      mu.label(ctx, s)

    case .Float:
      s := fmt.tprintf("%v: f32 = %v", tag.name, tag.value.float)
      mu.label(ctx, s)

    case .Double:
      s := fmt.tprintf("%v: f64 = %v", tag.name, tag.value.double)
      mu.label(ctx, s)

    case .ByteArray:
      s := fmt.tprintf("%v: [%v]i8", tag.name, tag.value.byte_array.count)
      mu.label(ctx, s)

    case .String:
      s := fmt.tprintf("%v: string = \"%v\"", tag.name, tag.value.str)
      mu.label(ctx, s)

    case .List:
      start_index := tag.value.list.start_index
      count := tag.value.list.count

      assert(count >= 0)
      s := fmt.tprint(tag.name, len(tag.name) != 0 ? ": " : "", count, " items", sep = "")
      if .ACTIVE in mu.treenode(ctx, s) {
        for i : i32 = 0; i < count; i += 1 {
          tag := appstate.header.tags[start_index + u32(i)]

          mu.push_id_rawptr(ctx, &i, size_of(i))
          draw_tag(ctx, appstate, tag)
          mu.pop_id(ctx)
        }
      }

    case .Compound:
      start_index := tag.value.compound.start_index
      count := tag.value.compound.count

      assert(count >= 0)
      s := fmt.tprint(tag.name, len(tag.name) != 0 ? ": " : "", count, " tags", sep = "")
      if .ACTIVE in mu.treenode(ctx, s, opt = { } ) {
        for i : i32 = 0; i < count; i += 1 {
          tag := appstate.header.tags[start_index + u32(i)]

          mu.push_id_rawptr(ctx, &i, size_of(i))
          draw_tag(ctx, appstate, tag)
          mu.pop_id(ctx)
        }
      }

    case .IntArray:
      s := fmt.tprintf("%v: [%v]i32", tag.name, tag.value.int_array.count)
      mu.label(ctx, s)

    case .LongArray:
      s := fmt.tprintf("%v: [%v]i32", tag.name, tag.value.long_array.count)
      mu.label(ctx, s)

    case:
      assert(false)
  }
}

draw_nbt_header :: proc(ctx: ^mu.Context, appstate : ^nbtfinder.AppState, header : ^nbtfinder.NBT_Decoded_Header) {
  root_tag := header.tags[header.root_tag_index]

  draw_tag(ctx, appstate, root_tag)
}
*/

// Define some colors.
COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}
COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
COLOR_BLACK :: clay.Color{0, 0, 0, 255}

Clay_Images :: struct {
  profile: rawptr
}


clay_draw_commands :: proc(appstate: ^nbtfinder.AppState, images: Clay_Images) -> clay.ClayArray(clay.RenderCommand) {
  // Layout config is just a struct that can be declared statically, or inline


  // Re-useable components are just normal procs.
  sidebar_item_component :: proc(index: u32) {
    sidebar_item_layout := clay.LayoutConfig {
        sizing = {
            width = clay.SizingGrow({}),
            height = clay.SizingFixed(50)
        },
    }
    
    if clay.UI(clay.ID("SidebarBlob", index))({
        layout = sidebar_item_layout,
        backgroundColor = COLOR_ORANGE
    }) {
      clay.Text(
          "teste gene",
          { textColor = COLOR_BLACK, fontSize = 16 },
      )
    }
  }

  clay.BeginLayout()
    // An example of laying out a UI with a fixed-width sidebar and flexible-width main content
    // NOTE: To create a scope for child components, the Odin API uses `if` with components that have children
    if clay.UI(clay.ID("OuterContainer"))({
        layout = {
            sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) },
            padding = { 16, 16, 16, 16 },
            childGap = 16,
        },
        backgroundColor = { 250, 250, 255, 255 },
    }) {
        if clay.UI(clay.ID("SideBar"))({
            layout = {
                layoutDirection = .TopToBottom,
                sizing = { width = clay.SizingFixed(300), height = clay.SizingGrow({}) },
                padding = { 16, 16, 16, 16 },
                childGap = 16,
            },
            backgroundColor = COLOR_LIGHT,
        }) {
            if clay.UI(clay.ID("ProfilePictureOuter"))({
                layout = {
                    sizing = { width = clay.SizingGrow({}) },
                    padding = { 16, 16, 16, 16 },
                    childGap = 16,
                    childAlignment = { y = .Center },
                },
                backgroundColor = COLOR_RED,
                cornerRadius = { 6, 6, 6, 6 },
            }) {
                if clay.UI(clay.ID("ProfilePicture"))({
                    layout = {
                        sizing = { width = clay.SizingFixed(60), height = clay.SizingFixed(60) },
                    },
                    image = {
                        // How you define `profile_picture` depends on your renderer.
                        imageData = images.profile,
                    },
                }) {}

                clay.Text(
                    "Clay - UI Library",
                    { textColor = COLOR_BLACK, fontSize = 16 },
                )
            }

            // Standard Odin code like loops, etc. work inside components.
            // Here we render 5 sidebar items.
            for i in u32(0)..<5 {
                sidebar_item_component(i)
            }
        }

        if clay.UI(clay.ID("MainContent"))({
            layout = {
                sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) },
            },
            backgroundColor = COLOR_LIGHT,
        }) {}
    }
  // TODO: fix deltatime
  return clay.EndLayout(0)
}


