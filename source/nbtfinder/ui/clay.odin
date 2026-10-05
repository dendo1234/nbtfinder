package ui
// NOTE(dendo): not sure how to proprly architecture the UI, shouldn't be skiping handmade lessons

import "base:runtime"
import "../"
import "core:fmt"
import "core:time"
import clay "clay:clay-odin"

Pool_Item :: struct {
  id : u32,
  last_updated : i32
}

ScrollBar_State :: struct {
  grab_pos: f32,
  start_pos: f32
}

Clay_State :: struct {
  print_types: bool,
  enable_drag: bool,

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
  
  // NOTE: if grab_pos = 0 -> not grabbing
  // NOTE(dendo): can this break if the mouse grab at pixel 0?
  vertical_scrollbar: ScrollBar_State,
  horizontal_scrollbar: ScrollBar_State,

  animation_distance_extra: u32,

  time_to_delay: f32
}

claystate : ^Clay_State

// Define some colors.
COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}
COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
COLOR_BLACK :: clay.Color{0, 0, 0, 255}
COLOR_LIGHT_GREY :: clay.Color{200, 200, 200, 255}
COLOR_WHITE :: clay.Color{255, 255, 255, 255}

TREENODE_IDENT :: 16

LAYOUT_TREE_BODY : clay.LayoutConfig : {
  padding = { TREENODE_IDENT, 0, 0, 0 },
  layoutDirection = .TopToBottom,
  childGap = 4,
}

icon_config: clay.ElementDeclaration = {
  layout = {
    sizing = { width = clay.SizingFixed(16), height = clay.SizingFixed(16)},
  }
}

tag_config: clay.ElementDeclaration = {
  layout = {
    padding = clay.PaddingAll(2),
    childGap = 4,
    layoutDirection = .LeftToRight
  },
  backgroundColor = COLOR_LIGHT_GREY
}

default_text: clay.TextElementConfig : {
  fontSize = 16,
  textColor = COLOR_BLACK,
  wrapMode = .Newlines
}

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

DelayedEaseOut :: proc "cdecl" (arguments: clay.TransitionCallbackArguments) -> bool {
  time := arguments.initial.borderColor[0]
  if arguments.elapsedTime < time {
    return false
  }
  _arg := arguments
  _arg.elapsedTime -= time

  ret := clay.EaseOut(_arg)
  return ret
}

EnterExitSlide :: proc "cdecl" (initialState: clay.TransitionData, properties: clay.TransitionPropertyFlags) -> clay.TransitionData {
  targetState := initialState
  if (.X in properties) {
    targetState.boundingBox.x -= 30 + f32(claystate.animation_distance_extra)
    //claystate.animation_distance_extra += 10
  }
  if (.OverlayColor in properties) {
    targetState.overlayColor = {255, 255, 255, 255}
  }

  // assert(!(.BorderColor in properties))
  targetState.borderColor[0] = claystate.time_to_delay
  claystate.time_to_delay += 0.02

  return targetState
}

clay_draw_tag :: proc(header : nbtfinder.NBT_Decoded_Header, tag : ^nbtfinder.NBT_Tag, child_index: u32 = 0) {
  clay_basic_tag :: proc(text : string, image: rawptr, child_index: u32) {
    if clay.UI(clay.ID_LOCAL("Tag", child_index))({
      layout = {
        padding = { 4, 4, 2, 2 },
        childGap = 4,
        layoutDirection = .LeftToRight
      },
      cornerRadius = clay.CornerRadiusAll(2),
      backgroundColor = clay.Hovered() ? COLOR_LIGHT_GREY : {},
      transition = {
        handler = DelayedEaseOut,
        duration = 0.2,
        // A "flag" enum is used to specify which properties to transition, use a bitwise OR (|) to construct the flags.
        properties = { .X, .OverlayColor },
        interactionHandling = .AllowInteractionsWhileTransitioningPosition,
        enter = { 
          setInitialState = EnterExitSlide,
          trigger = .TriggerOnFirstParentFrame
        },
        exit = { 
          setFinalState = EnterExitSlide,
          //trigger = .TriggerWhenParentExits
        },
      }
    }) {
      config := icon_config
      config.image.imageData = image
      if clay.UI()(config) {}
      clay.Text(text, default_text)
    }
  } // end clay_basic_tag

  clay_dropdown_tag :: proc (header: nbtfinder.NBT_Decoded_Header, text: string, image: rawptr, child_index: u32, list_tag: nbtfinder.NBT_Tag) {
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

    start_index: u32 = list_tag.value.list.start_index
    count: i32
    if list_tag.type == .Compound {
      count = list_tag.value.compound.count
    } else {
      assert(list_tag.type == .List)
      count = list_tag.value.list.count & 0x00ffffff
    }

    taglist_id := clay.ID_LOCAL("TagList", child_index)
    if clay.UI(taglist_id)({
      layout = {
        layoutDirection = .TopToBottom,
        childGap = 4
      }
    }) {

      // DESC: HEADER
      if clay.UI(clay.ID_LOCAL("TagListHeader"))({
        layout = {
          padding = { 4, 4, 2, 2 },
          childGap = 4,
          layoutDirection = .LeftToRight
        },
        cornerRadius = clay.CornerRadiusAll(2),
        backgroundColor = clay.Hovered() ? COLOR_LIGHT_GREY : {},
        transition = {
          handler = DelayedEaseOut,
          duration = 0.2,
          // A "flag" enum is used to specify which properties to transition, use a bitwise OR (|) to construct the flags.
          properties = { .X, .OverlayColor } | clay.TransitionPropertyBoundingBox,
          interactionHandling = .AllowInteractionsWhileTransitioningPosition,
          enter = { 
            setInitialState = EnterExitSlide,
            trigger = .TriggerOnFirstParentFrame
          },
          exit = { 
            setFinalState = EnterExitSlide,
            //trigger = .TriggerWhenParentExits
          },
        }
      }) {
        config := icon_config
        config.image.imageData = image
        if clay.UI()(config) {}
        clay.Text(text, default_text)

        if (count > 0) {
          clay.OnHover(tree_hover, rawptr(uintptr(taglist_id.id)))
        }
      }
        // NOTE: one frame delay on the update of the mouse click

        idx := pool_get(claystate.treepool[:], taglist_id.id)
        active := idx >= 0

        if (active && count > 0) {
          pool_update(claystate.treepool[:], idx, claystate.current_frame)

          // DESC: CHILDREN
          if clay.UI(clay.ID_LOCAL("TagListBody"))({
            layout = LAYOUT_TREE_BODY
          }) {
            if list_tag.type == .Compound {
              for child_index : i32 = 0; child_index < count; child_index += 1 {
                tag := header.tags[start_index + u32(child_index)]

                clay_draw_tag(header, &tag, u32(child_index))
              }
            } else {
              for child_index : i32 = 0; child_index < count; child_index += 1 {
                tag : nbtfinder.NBT_Tag
                tag.type = list_tag.value.list.children_type
                tag.value = header.unnamed_tags[start_index + u32(child_index)]

                clay_draw_tag(header, &tag, u32(child_index))
              }
            }
          }
        }
      }
    } // end clay_dropdown_tag

  text: string
  image: rawptr

  type_name: string
  tag_name := nbtfinder.nbt_string_get(&tag.name, header)
  value: any // crazy RTTI
  print_scalar_like: bool

  switch tag.type {
    case .End:
      assert(false)

    case .Byte:
      type_name = "i8"
      value = tag.value.byte
      image = claystate.images.names.tag_icons.byte
      print_scalar_like = true

    case .Short:
      type_name = "i16"
      value = tag.value.short
      image = claystate.images.names.tag_icons.short
      print_scalar_like = true

    case .Int:
      type_name = "i32"
      value = tag.value.integer
      image = claystate.images.names.tag_icons.int
      print_scalar_like = true

    case .Long:
      type_name = "i64"
      value = tag.value.long
      image = claystate.images.names.tag_icons.long
      print_scalar_like = true

    case .Float:
      type_name = "f32"
      value = tag.value.float
      image = claystate.images.names.tag_icons.float
      print_scalar_like = true

    case .Double:
      type_name = "f64"
      value = tag.value.double
      image = claystate.images.names.tag_icons.double
      print_scalar_like = true

    case .ByteArray:
      type_name = "i8"
      value = tag.value.byte_array.count
      image = claystate.images.names.tag_icons.byte_array
      print_scalar_like = false

    case .String:
      type_name = "string"
      value_str := nbtfinder.nbt_string_get(&tag.value.str, header)

      value = value_str
      image = claystate.images.names.tag_icons.string
      print_scalar_like = true

    case .List:
      count := tag.value.list.count & 0x00ffffff

      type_name = "NBT_Value"
      value = count
      image = claystate.images.names.tag_icons.list
      print_scalar_like = false

    case .Compound:
      count := tag.value.compound.count

      type_name = "NBT_Tag"
      value = count
      image = claystate.images.names.tag_icons.compound
      print_scalar_like = false

    case .IntArray:
      type_name = "i32"
      value = tag.value.int_array.count
      image = claystate.images.names.tag_icons.int_array
      print_scalar_like = false

    case .LongArray:
      type_name = "i64"
      value = tag.value.long_array.count
      image = claystate.images.names.tag_icons.long_array
      print_scalar_like = false

    case:
      assert(false)
  }
 
  format_string: string
  if print_scalar_like {
    if len(tag_name) == 0 {
      if claystate.print_types == true {
        text = fmt.tprintf("%T = %[0]w", value)
      } else {
        text = fmt.tprintf("%w", value)
      }
    } else {
      if claystate.print_types == true {
        text = fmt.tprintf("%v: %T = %[1]w", tag_name, value)
      } else {
        text = fmt.tprintf("%v: %w", tag_name, value)
      }
    }
  } else {
    // print list like
    if len(tag_name) == 0 {
      if claystate.print_types == true {
        text = fmt.tprintf("[%v]%v", value, type_name)
      } else {
        text = fmt.tprintf("[%v]", value)
      }
    } else {
      if claystate.print_types == true {
        text = fmt.tprintf("%v: [%v]%v", tag_name, value, type_name)
      } else {
        text = fmt.tprintf("%v: [%v]", tag_name, value)
      }
    }
  }

  if tag.type == .Compound || tag.type == .List {
    clay_dropdown_tag(header, text, image, child_index, tag^)
  } else {
    clay_basic_tag(text, image, child_index)
  }
}

clay_draw_nbt_header :: proc(header : nbtfinder.NBT_Decoded_Header) {
  root_tag := header.tags[header.root_tag_index]

  clay_draw_tag(header, &root_tag)
}

clay_is_scrolling :: proc(claystate: Clay_State) -> bool {
  return claystate.vertical_scrollbar.grab_pos != 0 || claystate.horizontal_scrollbar.grab_pos != 0
}

clay_files :: proc(appstate: ^nbtfinder.AppState) {
  if clay.UI(clay.ID("SelectedFiles"))({
    layout = {
      layoutDirection = .TopToBottom
    }
  }) {
    for file_index := 0; file_index < len(appstate.file_store.staged_files); file_index += 1 {
      assert(file_index < (1 << 32) - 1)

      file_id := clay.ID_LOCAL("File", u32(file_index))
      if clay.UI(file_id)({
        layout = {
          layoutDirection = .TopToBottom,
          childGap = 4
        }
      }) {
        id := file_id.id

        idx := pool_get(claystate.treepool[:], id)
        active := idx >= 0

        if clay.UI(clay.ID_LOCAL("FileHeader", u32(file_index)))({
          layout = {
            padding = { 4, 4, 2, 2 },
            childGap = 4,
            layoutDirection = .LeftToRight
          },
          cornerRadius = clay.CornerRadiusAll(2),
          backgroundColor = clay.Hovered() ? COLOR_LIGHT_GREY : {},
          transition = {
            handler = DelayedEaseOut,
            duration = 0.2,
            // A "flag" enum is used to specify which properties to transition, use a bitwise OR (|) to construct the flags.
            properties = { .X, .OverlayColor } | clay.TransitionPropertyBoundingBox,
            interactionHandling = .AllowInteractionsWhileTransitioningPosition,
            enter = { 
              setInitialState = EnterExitSlide,
              trigger = .TriggerOnFirstParentFrame
              },
              exit = { 
                setFinalState = EnterExitSlide,
                //trigger = .TriggerWhenParentExits
              },
            }
          }) {
            if clay.Hovered() && clay.GetPointerState().state == .PressedThisFrame {
              if active {
                // toggle
                claystate.treepool[idx].id = 0
                claystate.treepool[idx].last_updated = 0
              } else {
                idx = pool_add(claystate.treepool[:], id, claystate.current_frame)

                file := appstate.file_store.staged_files[file_index]

                handler, err := nbtfinder.get_or_open_file(appstate, file_index)
                assert(err == nil)

                active = true
              }
            }

            filename := appstate.file_store.staged_files[file_index].filename
            assert(len(filename) > 1)

            clay.Text(filename, default_text)
          }



          if (active) {
            pool_update(claystate.treepool[:], idx, claystate.current_frame)

            if clay.UI(clay.ID_LOCAL("FileBody"))({
              layout = LAYOUT_TREE_BODY
            }) {
              handler, err := nbtfinder.get_or_open_file(appstate, file_index)
              assert(err == nil)

              switch v in handler.data {
                case ^nbtfinder.NBT_Decoded_Header:
                  clay_draw_nbt_header(v^)
                case nbtfinder.MCA_File_Header:
                case:
              }
            }
          }
        }
      }
    }
}

clay_nbt_browser :: proc(appstate: ^nbtfinder.AppState) {
  move_scrollbar :: proc(mouse_relative_percentage: f32, view_percent: f32, content_size: f32, out_pos: ^f32) {
    m := mouse_relative_percentage
    m = min(mouse_relative_percentage, 1 - view_percent/2)
    m -= view_percent/2
    m = max(mouse_relative_percentage, 0)

    out_pos^ = -mouse_relative_percentage*content_size
  }

  vertical_scrollbar :: proc(container_id: clay.ElementId) -> bool {
    scrollbar_hover_vertical :: proc "c" (id: clay.ElementId, pointerData: clay.PointerData, userData: rawptr) {
      if pointerData.state == .PressedThisFrame {
        scroll_data := clay.GetScrollContainerData(id)

        (^ScrollBar_State)(userData).grab_pos = pointerData.position[1]
        (^ScrollBar_State)(userData).start_pos = scroll_data.config.childOffset[1]
      }
    }

    scroll_data := clay.GetScrollContainerData(container_id)

    if scroll_data.contentDimensions.height > scroll_data.scrollContainerDimensions.height {
      view_percent := f32(scroll_data.scrollContainerDimensions.height)/f32(scroll_data.contentDimensions.height)
      bar_percent := (-scroll_data.scrollPosition[1] / scroll_data.contentDimensions.height)
      //bar_percent = bar_percent-view_percent/2
      bar_percent = max(bar_percent, 0)
      bar_percent = min(bar_percent, 1)
      bar_pos := bar_percent*scroll_data.scrollContainerDimensions.height

      // DESC: VERTICAL SCROLLBAR
      if clay.UI()({
        layout = {
          sizing = { width = clay.SizingFixed(8), height = clay.SizingGrow() }
        },
        clip = {
          vertical = true,
          childOffset = {0, bar_pos}
        },
        backgroundColor = COLOR_BLACK,
      }) {
        move_scrollbar_vertical :: proc (id, outer_id: clay.ElementId, scrollbar_state: ScrollBar_State, pointerData: clay.PointerData) {
          outer_scroll_data := clay.GetScrollContainerData(outer_id)
          bar_scroll_data := clay.GetScrollContainerData(id)
          scroll_element := clay.GetElementData(id)

          view_percent := f32(outer_scroll_data.scrollContainerDimensions.height)/f32(outer_scroll_data.contentDimensions.height)
          relative_y_pixel := pointerData.position[1] - scrollbar_state.grab_pos + scrollbar_state.start_pos
          relative_y_percentage := relative_y_pixel / bar_scroll_data.scrollContainerDimensions.height

          move_scrollbar(relative_y_percentage, view_percent, outer_scroll_data.contentDimensions.height, &outer_scroll_data.scrollPosition[1])
        }

        scrollbar_id: clay.ElementId = {
          id = clay.GetOpenElementId()
        }
        pointerState := clay.GetPointerState()

        if pointerState.state == .Released {
          claystate.vertical_scrollbar.grab_pos = 0
        }

        if claystate.vertical_scrollbar.grab_pos != 0 {
          move_scrollbar_vertical(scrollbar_id, container_id, claystate.vertical_scrollbar, clay.GetPointerState())
        }

        clay.OnHover(scrollbar_hover_vertical, &claystate.vertical_scrollbar)

        if clay.UI()({
          layout = {
            sizing = { width = clay.SizingFixed(8), height = clay.SizingPercent(view_percent) }
          },
          backgroundColor = COLOR_LIGHT,
        }) {}
      } // vertical scrollbar
      return true
    }
    return false
  }

  horizontal_scrollbar :: proc(container_id: clay.ElementId) -> bool {
    scrollbar_hover_horizontal :: proc "c" (id: clay.ElementId, pointerData: clay.PointerData, userData: rawptr) {
      if pointerData.state == .PressedThisFrame {
        scroll_data := clay.GetScrollContainerData(id)

        (^ScrollBar_State)(userData).grab_pos = pointerData.position[0]
        (^ScrollBar_State)(userData).start_pos = scroll_data.config.childOffset[0]
      }
    }

    scroll_data := clay.GetScrollContainerData(container_id)

    if scroll_data.contentDimensions.width > scroll_data.scrollContainerDimensions.width {
      view_percent := f32(scroll_data.scrollContainerDimensions.width)/f32(scroll_data.contentDimensions.width)
      bar_percent := (-scroll_data.scrollPosition[0] / scroll_data.contentDimensions.width)
      //bar_percent = bar_percent-view_percent/2
      bar_percent = max(bar_percent, 0)
      bar_percent = min(bar_percent, 1)
      bar_pos := bar_percent*scroll_data.scrollContainerDimensions.width

      // DESC: HORIZONTAL SCROLLBAR
      if clay.UI()({
        layout = {
          sizing = { width = clay.SizingGrow(), height = clay.SizingFixed(8) }
        },
        clip = {
          horizontal = true,
          childOffset = {bar_pos, 0}
        },
        backgroundColor = COLOR_BLACK,
      }) {
        move_scrollbar_horizontal :: proc (id, outer_id: clay.ElementId, scrollbar_state: ScrollBar_State, pointerData: clay.PointerData) {
          outer_scroll_data := clay.GetScrollContainerData(outer_id)
          bar_scroll_data := clay.GetScrollContainerData(id)
          scroll_element := clay.GetElementData(id)

          view_percent := f32(outer_scroll_data.scrollContainerDimensions.width)/f32(outer_scroll_data.contentDimensions.width)
          element_data := clay.GetElementData(id)
          relative_x_pixel := pointerData.position[0] - scrollbar_state.grab_pos + scrollbar_state.start_pos

          relative_x_percentage := relative_x_pixel / scroll_element.boundingBox.width

          move_scrollbar(relative_x_percentage, view_percent, outer_scroll_data.contentDimensions.width, &outer_scroll_data.scrollPosition[0])
        }

        scrollbar_id: clay.ElementId = {
          id = clay.GetOpenElementId()
        }
        pointerState := clay.GetPointerState()

        if pointerState.state == .Released {
          claystate.horizontal_scrollbar.grab_pos = 0
        }

        if claystate.horizontal_scrollbar.grab_pos != 0 {
          move_scrollbar_horizontal(scrollbar_id, container_id, claystate.horizontal_scrollbar, clay.GetPointerState())
        }

        clay.OnHover(scrollbar_hover_horizontal, &claystate.horizontal_scrollbar)

        if clay.UI()({
          layout = {
            sizing = { width = clay.SizingPercent(view_percent), height = clay.SizingFixed(8) }
          },
          backgroundColor = COLOR_LIGHT,
        }) {}
      } // horizontal scrollbar
      return true
    }
    return false
  }

  if clay.UI(clay.ID("NBTBrowser"))({
    layout = {
        sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) },
        padding = { 16, 16, 16, 16 },
        layoutDirection = .TopToBottom
    },
  }) {
    rendered_vertical: bool
    content_id : clay.ElementId

    // DESC: up part
    if clay.UI()({
      layout = {
        sizing = { width = clay.SizingGrow(), height = clay.SizingGrow() },
        layoutDirection = .LeftToRight
      }
    }) {
      content_id = clay.ID_LOCAL("Content")

      if clay.UI(content_id)({
        layout = {
          sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) },
        },
        clip = {
          horizontal = true,
          vertical = true,
          childOffset = clay.GetScrollOffset()
        }
      }) {
        clay_files(appstate)
      }

      rendered_vertical = vertical_scrollbar(content_id)
    }

    // DESC: down part
    if clay.UI()({
      layout = {
        sizing = { width = clay.SizingGrow(), height = clay.SizingGrow() },
        layoutDirection = .LeftToRight
      }
    }) {

      assert(content_id.id != 0)
      rendered_horizontal := horizontal_scrollbar(content_id)

      if rendered_vertical && rendered_horizontal {

        // little square
        if clay.UI()({
          layout = {
            sizing = { width = clay.SizingFixed(8), height = clay.SizingFixed(8) }
          },
          backgroundColor = COLOR_BLACK
        }) {

        }
      }

    }


  } // NBTBrowser
}

clay_draw_commands :: proc(appstate: ^nbtfinder.AppState, claystateptr: ^Clay_State, delta_time: f32) -> clay.ClayArray(clay.RenderCommand) {
  claystate = claystateptr

  claystate.current_frame += 1
  claystate.animation_distance_extra = 0
  claystate.time_to_delay = 0

  //clay.SetDebugModeEnabled(true)

  clay.BeginLayout()
    if clay.UI(clay.ID("OuterContainer"))({
        layout = {
            sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) },
            padding = { 16, 16, 16, 16 },
            childGap = 16,
            layoutDirection = .TopToBottom
        },
        backgroundColor = { 255, 255, 255, 255 },
    }) {
      count := pool_count_active(claystate.treepool[:], claystate.current_frame - 1)

      clay_nbt_browser(appstate)

      if clay.UI()({
        layout = {
          sizing = { width = clay.SizingFixed(32), height = clay.SizingFixed(32) }
        },
        backgroundColor = COLOR_ORANGE
      }) {
        if clay.Hovered() && clay.GetPointerState().state == .PressedThisFrame {
          claystate.print_types = !claystate.print_types
        }
      }
      if clay.UI(clay.ID("StatusBar"))({
        layout = {
          sizing = { width = clay.SizingGrow(), height = clay.SizingFit() }
        }
      }) {
        if clay.UI()({}) {
          text := fmt.tprintf("open: %v/48", count)
          clay.Text(text, default_text)
        }

        if clay.UI()({
          layout = {
            sizing = { width = clay.SizingGrow(), height = clay.SizingFit() }
          }
        }) {

        }

        if clay.UI()({}) {
          frame_duration := appstate.last_frame_duration

          text := fmt.tprintf("frame:%.4v", frame_duration)
          clay.Text(text, default_text)
        }
      }
    }



  return clay.EndLayout(delta_time)
}


