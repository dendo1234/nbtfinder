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

CPU_Feature :: enum {
  SIMD_128_bits,
  SIMD_256_bits,
  SIMD_512_bits
}

CPU_Features :: bit_set[CPU_Feature]


init :: proc(appstate : ^AppState, cpu_features : CPU_Features) -> (mu_context : ^mu.Context, ok : bool) {

  mu.init(&appstate.mu_context)

  mu_context = &appstate.mu_context;
  mu_context.text_width  = mu.default_atlas_text_width
  mu_context.text_height = mu.default_atlas_text_height

  run_tests(cpu_features)

  return mu_context, true
}

