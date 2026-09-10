package nbtfinder

import mu "vendor:microui"

WindowSpecifications :: struct {
  title : string,
  width : i32,
  height : i32,
}
window_specs : WindowSpecifications : {
  title = "nbtfinder\x00",
  width = 400,
  height = 600
}
#assert (window_specs.title[len(window_specs.title)-1] == 0)

AppState :: struct {
  mu_context : mu.Context,
  header : ^NBT_Decoded_Header
}

init :: proc(appstate : ^AppState) -> (mu_context : ^mu.Context, ok : bool) {

  mu.init(&appstate.mu_context)

  mu_context = &appstate.mu_context;
  mu_context.text_width  = mu.default_atlas_text_width
  mu_context.text_height = mu.default_atlas_text_height

  //run_tests()

  return mu_context, true
}

