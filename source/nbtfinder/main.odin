package nbtfinder

import "core:fmt"
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

Compute_Methods :: enum {
  Scalar = 0,
  SIMD_128_bits = 1,
  SIMD_256_bits = 2,
  SIMD_512_bits = 3
}

AppState :: struct {
  compute_method: Compute_Methods,
  header: ^NBT_Decoded_Header
}

CPU_Feature :: enum {
  SIMD_128_bits,
  SIMD_256_bits,
  SIMD_512_bits
}

CPU_Features :: bit_set[CPU_Feature]

init :: proc(appstate : ^AppState, cpu_features : CPU_Features) -> (ok : bool) {

  best := run_tests(cpu_features)

  fmt.println(best)
  appstate.compute_method = best

  switch (best) {
    case .Scalar:
    case .SIMD_128_bits:
    case .SIMD_256_bits:
    case .SIMD_512_bits:
  }

  return true
}

