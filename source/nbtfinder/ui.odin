package nbtfinder
// NOTE(dendo): not sure how to proprly architecture the UI, shouldn't be skiping handmade lessons

import "core:fmt"
import mu "vendor:microui"

microui_draw_commands :: proc(appstate : ^AppState, rect : mu.Rect) {
  ctx := &appstate.mu_context

  mu.begin(ctx)
  {
    if mu.begin_window(ctx, window_specs.title, rect, { .NO_CLOSE, .NO_RESIZE }) {
      win := mu.get_current_container(ctx);
      win.rect.w = rect.w;
      win.rect.h = rect.h;

      if .SUBMIT in mu.button(ctx, "test") {
        fmt.println("Button Press")
      }

      for tag in appstate.header.tags {
        if (tag.name != "") {
          mu.text(ctx, tag.name)
        }
      }

      mu.end_window(ctx)
    }
  }
  mu.end(ctx)
}


