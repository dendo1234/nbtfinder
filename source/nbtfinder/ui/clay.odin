package ui
// NOTE(dendo): not sure how to proprly architecture the UI, shouldn't be skiping handmade lessons

import "base:runtime"
import "../"
import "core:fmt"
import clay "clay:clay-odin"

// Define some colors.
COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}
COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
COLOR_BLACK :: clay.Color{0, 0, 0, 255}

Pool_Item :: struct {
  id : u32,
  last_updated : i32
}

TREENODE_IDENT :: 16

Clay_State :: struct {
  images: struct #raw_union {
    names: struct {
      tag_icons: struct {
        end: rawptr,
        byte: rawptr,
        short: rawptr,
        int: rawptr,
        long: rawptr,
        float: rawptr,
        double: rawptr,
        byte_array: rawptr,
        string: rawptr,
        list: rawptr,
        compound: rawptr,
        int_array: rawptr,
        long_array: rawptr
      },
      profile: rawptr
    },
    raw: [14]rawptr
  },
  treepool: [48]Pool_Item,
  current_frame: i32,
  //current_ident: u16,
}

claystate : ^Clay_State

pool_add :: proc "contextless" (pool: []Pool_Item, id: u32, current_frame: i32) -> (idx: i32) {
  context = runtime.default_context()

  free_index := -1
  frame := current_frame
  for i := 0; i < len(pool); i += 1 {
    if pool[i].last_updated < frame {
      // is available
      free_index = i
      frame = pool[i].last_updated
    }
  }
  // TODO(dendo): remove this assert
  assert(free_index != -1)

  pool[free_index].id = id
  pool[free_index].last_updated = current_frame

  return i32(free_index)
}

pool_update :: proc(pool: []Pool_Item, idx: i32, current_frame: i32) {
  pool[idx].last_updated = current_frame
}

pool_get :: proc "contextless" (pool: []Pool_Item, id: u32) -> (idx: i32) {
  for i := 0; i < len(pool); i += 1 {
    if pool[i].id == id {
      return i32(i)
    }
  }
  return -1
}

pool_count_active :: proc (pool: []Pool_Item, frame: i32) -> int {
  count := 0
  for i := 0; i < len(pool); i += 1 {
    if (pool[i].last_updated >= frame) {
      count += 1
    }
  }
  return count

}

SizingFit :: proc "contextless" (sizeMinMax: clay.SizingConstraintsMinMax = {}) -> clay.SizingAxis {
    return clay.SizingAxis{type = clay.SizingType.Fit, constraints = {sizeMinMax = sizeMinMax}}
}

SizingGrow :: proc "contextless" (sizeMinMax: clay.SizingConstraintsMinMax = {}) -> clay.SizingAxis {
    return clay.SizingAxis{type = clay.SizingType.Grow, constraints = {sizeMinMax = sizeMinMax}}
}

SizingFixed :: proc "contextless" (size: f32) -> clay.SizingAxis {
    return clay.SizingAxis{type = clay.SizingType.Fixed, constraints = {sizeMinMax = {size, size}}}
}

SizingPercent :: proc "contextless" (sizePercent: f32) -> clay.SizingAxis {
    return clay.SizingAxis{type = clay.SizingType.Percent, constraints = {sizePercent = sizePercent}}
}

icon_config: clay.ElementDeclaration = {
  layout = {
    sizing = { width = SizingFixed(16), height = SizingFixed(16)},
  }
}

default_text: clay.TextElementConfig : {
  fontSize = 16,
  textColor = COLOR_BLACK
}

clay_draw_tag :: proc(appstate : ^nbtfinder.AppState, tag : nbtfinder.NBT_Tag) {
  clay_listlike_config: clay.ElementDeclaration : {
    layout = {
      layoutDirection = .TopToBottom
    }
  }


  tree_hover :: proc "c" (id: clay.ElementId, pointerData: clay.PointerData, userData: rawptr) {
    id := u32(uintptr(userData))

    idx := pool_get(claystate.treepool[:], id)
    active := idx >= 0
    if pointerData.state == .PressedThisFrame {
      if idx == -1 {
        idx = pool_add(claystate.treepool[:], id, claystate.current_frame)
      } else {
        claystate.treepool[idx].id = 0
        claystate.treepool[idx].last_updated = 0

      }

    }
  }

  tag_config: clay.ElementDeclaration : {
    layout = {
      layoutDirection = .LeftToRight
    }
  }


  dropdown :: proc (appstate: ^nbtfinder.AppState, text: string, image: rawptr, start_index: u32, count: i32) {
    assert(count >= 0)

    id: u32

    // DESC: HEADER
    if clay.UI()(tag_config) {
      config := icon_config
      config.image.imageData = image
      if clay.UI()(config) {}
      clay.Text(text, default_text)

      id = clay.GetOpenElementId()
      if (count > 0) {
        clay.OnHover(tree_hover, rawptr(uintptr(id)))
      }
    }

    // NOTE: one frame delay on the update of the mouse click

    idx := pool_get(claystate.treepool[:], id)
    active := idx >= 0

    if (active && count > 0) {
      pool_update(claystate.treepool[:], idx, claystate.current_frame)

      config := clay_listlike_config
      config.layout.padding.left = TREENODE_IDENT
      // DESC: CHILDREN
      if clay.UI()(config) {
        for i : i32 = 0; i < count; i += 1 {
          tag := appstate.header.tags[start_index + u32(i)]

          // NOTE: ID is auto assigned by clay
          clay_draw_tag(appstate, tag)
        }
      }

    }
  }

  if clay.UI()(clay_listlike_config) {
    start_index : u32
    count : i32
    text: string
    image: rawptr

    switch tag.type {
      case .End:
        assert(false)

      case .Byte:
        text = fmt.tprintf("%v: i8 = %v", tag.name, tag.value.byte)
        image = claystate.images.names.tag_icons.byte

      case .Short:
        text = fmt.tprintf("%v: i16 = %v", tag.name, tag.value.short)
        image = claystate.images.names.tag_icons.short

      case .Int:
        text = fmt.tprintf("%v: i32 = %v", tag.name, tag.value.integer)
        image = claystate.images.names.tag_icons.int

      case .Long:
        text = fmt.tprintf("%v: i64 = %v", tag.name, tag.value.long)
        image = claystate.images.names.tag_icons.long

      case .Float:
        text = fmt.tprintf("%v: f32 = %v", tag.name, tag.value.float)
        image = claystate.images.names.tag_icons.float

      case .Double:
        text = fmt.tprintf("%v: f64 = %v", tag.name, tag.value.double)
        image = claystate.images.names.tag_icons.double

      case .ByteArray:
        text = fmt.tprintf("%v: [%v]i8", tag.name, tag.value.byte_array.count)
        image = claystate.images.names.tag_icons.byte_array

      case .String:
        text = fmt.tprintf("%v: string = \"%v\"", tag.name, tag.value.str)
        image = claystate.images.names.tag_icons.string

      case .List:
        start_index = tag.value.list.start_index
        count = tag.value.list.count

        text = fmt.tprint(tag.name, len(tag.name) != 0 ? ": " : "", count, " items", sep = "")
        image = claystate.images.names.tag_icons.list

      case .Compound:
        start_index = tag.value.compound.start_index
        count = tag.value.compound.count

        text = fmt.tprint(tag.name, len(tag.name) != 0 ? ": " : "", count, " tags", sep = "")
        image = claystate.images.names.tag_icons.compound

      case .IntArray:
        text = fmt.tprintf("%v: [%v]i32", tag.name, tag.value.int_array.count)
        image = claystate.images.names.tag_icons.int_array

      case .LongArray:
        text = fmt.tprintf("%v: [%v]i32", tag.name, tag.value.long_array.count)
        image = claystate.images.names.tag_icons.long_array

      case:
        assert(false)
    }

    if tag.type == .Compound || tag.type == .List {
      dropdown(appstate, text, image, start_index, count)
    } else {

      if clay.UI()(tag_config) {
        config := icon_config
        config.image.imageData = image
        if clay.UI()(config) {}
        clay.Text(text, default_text)
      }

    }
  }
}

clay_draw_nbt_header :: proc(appstate : ^nbtfinder.AppState, header : ^nbtfinder.NBT_Decoded_Header) {
  root_tag := header.tags[header.root_tag_index]

  clay_draw_tag(appstate, root_tag)
}

clay_draw_commands :: proc(appstate: ^nbtfinder.AppState, claystateptr: ^Clay_State, delta_time: f32) -> clay.ClayArray(clay.RenderCommand) {
  claystate = claystateptr

  claystate.current_frame += 1

  //clay.SetDebugModeEnabled(true)

  clay.BeginLayout()
    if clay.UI(clay.ID("OuterContainer"))({
        layout = {
            sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) },
            padding = { 16, 16, 16, 16 },
            childGap = 16,
            layoutDirection = .TopToBottom
        },
        backgroundColor = { 250, 250, 255, 255 },
    }) {
      count := pool_count_active(claystate.treepool[:], claystate.current_frame - 1)

      text := fmt.tprintf("Open Treenodes last frame: %v", count)


      if clay.UI(clay.ID("MainContent"))({
        layout = {
            sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) },
            padding = { 16, 16, 16, 16 },
            childGap = 16,
        },
        clip = {
          vertical = true,
          childOffset = clay.GetScrollOffset()
        }
      }) {
        clay_draw_nbt_header(appstate, appstate.header)
      }

      // DESC: STATUS BAR
      if clay.UI()({}) {
        clay.Text(text, default_text)
      }
    }



  return clay.EndLayout(delta_time)
}


