package nbtfinder

import "base:intrinsics"
import "base:runtime"
import "core:encoding/endian"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:slice"
import "core:simd"
import "core:time"

TEST_REPEAT_COUNT :: 4
STRIDE_COUNT :: 16

// NOTE: seting this atribute made the loop go faster, probraly due to code alignment
//@(optimization_mode="favor_size")
test_unaligned_scalar_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
  type :: i32
  when type == i32 {
    type_to_load :: i32be
  } else when type == i64 {
    type_to_load :: i64be
  }

  acc : type
  size := len(bytes) - STRIDE_COUNT
  // NOTE(dendo): warm the cache
  for index := 0; index < size; index += size_of(type) {
    acc += intrinsics.unaligned_load(cast(^type)&bytes[index])
  }
 

  for offset := 0; offset < STRIDE_COUNT; offset += 1 {
    tick := time.tick_now()

    for index := 0; index < size; index += size_of(type) {
      acc += type(intrinsics.unaligned_load(cast(^type_to_load)&bytes[index+offset]))
    }

    duration := time.tick_since(tick)
    durations[offset] = duration;
  }


  return int(acc)
}

// NOTE(dendo): this is most because of curiosity. The results are,
// that on a optimized build, this does one extra bounds check, which I don't know the reason of
test_unaligned_scalar_core_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
  type :: i32
  when type == i32 {
    get_func :: endian.unchecked_get_u32be
  } else when type == i64 {
    get_func :: endian.unchecked_get_u64be
  }

  acc : type
  size := len(bytes) - STRIDE_COUNT
  // NOTE(dendo): warm the cache
  for index := 0; index < size; index += size_of(type) {
    acc += intrinsics.unaligned_load(cast(^type)&bytes[index])
  }

  for offset := 0; offset < STRIDE_COUNT; offset += 1 {
    tick := time.tick_now()

    for index := 0; index < size; index += size_of(type) {
      acc += type(get_func(bytes[index+offset:]))
    }

    duration := time.tick_since(tick)
    durations[offset] = duration;
  }

  return int(acc)
}

test_unaligned_simd :: proc(bytes: []u8, durations: []time.Duration, $type: typeid, $simd_type: typeid) -> int {
  acc : type
  acc_vec: simd_type = 0
  size := len(bytes) - STRIDE_COUNT
  // NOTE(dendo): warm the cache
  for index := 0; index < size; index += size_of(type) {
    acc += intrinsics.unaligned_load(cast(^type)&bytes[index])
  }

  for offset := 0; offset < STRIDE_COUNT; offset += 1 {
    tick := time.tick_now()

    index := 0
    for ; index < size-(size_of(simd_type)); index += size_of(simd_type) {
      vec := intrinsics.unaligned_load(cast(^simd_type)&bytes[index+offset])
      vec = simd.byte_swap(vec)

      acc_vec = simd.add(acc_vec, vec)
    }

    assert(size - index <= size_of(simd_type))
    index_to_load : type = type(size-index) >> 2

    test : simd_type = index_to_load
    mask := simd.iota(simd_type)
    mask = simd_type(simd.lanes_lt(mask, test))

    vec := simd.masked_load(&bytes[index+offset], cast(simd_type)0, mask)
    vec = simd.byte_swap(vec)
    acc_vec = simd.add(acc_vec, vec)

    duration := time.tick_since(tick)
    durations[offset] = duration;
  }

  acc += simd.reduce_add_pairs(acc_vec)

  return int(acc)
}

test_unaligned_sse_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
  return test_unaligned_simd(bytes, durations, i32, #simd[4]i32)
}

test_unaligned_avx_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
  return test_unaligned_simd(bytes, durations, i32, #simd[8]i32)
}

test_unaligned_avx512_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
  return test_unaligned_simd(bytes, durations, i32, #simd[16]i32)
}

statistics_from_durations :: proc(durations: []time.Duration) -> (avg: time.Duration, p95 : time.Duration,  std_deviation: time.Duration) {
  size := len(durations)

  for i := 0; i < size; i += 1 {
    avg += durations[i]/time.Duration(size)
  }
  slice.reverse_sort(durations)

  count95 := size / 20

  for i := 0; i < count95; i += 1 {
    p95 += durations[i]/time.Duration(count95)
  }

  variance : f64 = 0
  for i := 0; i < size; i += 1 {
    deviation := f64(durations[i]) - f64(avg)
    variance += deviation*deviation
  }
  variance /= f64(size)
  std_deviation = time.Duration(math.sqrt(variance))

  return
}

run_test :: proc(
  bytes: []u8,
  durations: ^[dynamic]time.Duration,
  test_proc: proc(bytes: []u8, durations: []time.Duration) -> int,
  name : string,
  repetition_count: int = TEST_REPEAT_COUNT
) -> (avg: time.Duration, p95: time.Duration, std_deviation: time.Duration) {

  resize(durations, repetition_count * STRIDE_COUNT)

  result : int = 0
  for i := 0; i < repetition_count; i += 1 {
    result += test_proc(bytes, durations[i*STRIDE_COUNT:i*STRIDE_COUNT+STRIDE_COUNT])
  }
  avg, p95, std_deviation = statistics_from_durations(durations[:])
  fmt.printfln("%40v - result: %v, avg: %v, p95 : %v, std_deviation: %v", name, result, avg, p95, std_deviation)

  resize(durations, 0)
  return
}

run_tests :: proc() {
  stopwatch : time.Stopwatch

  time.stopwatch_reset(&stopwatch);

  MiB :: 5 << 20
  bytes, err := mem.alloc_bytes_non_zeroed(MiB, alignment = mem.DEFAULT_ALIGNMENT)
  durations, err2 := make([dynamic]time.Duration, 0, 16)

  assert(err == .None && err2 == .None)

  rand_gen := runtime.default_random_generator()
  ok := runtime.random_generator_read_bytes(rand_gen, bytes)

  assert(ok)


  fmt.println("Starting performance tests")
  run_test(bytes, &durations, test_unaligned_scalar_core_i32be, "test_unaligned_scalar_core_i32be")
  run_test(bytes, &durations, test_unaligned_scalar_i32be, "test_unaligned_scalar_i32be")
  run_test(bytes, &durations, test_unaligned_sse_i32be , "test_unaligned_sse_i32be")
  run_test(bytes, &durations, test_unaligned_avx_i32be , "test_unaligned_avx_i32be")
  run_test(bytes, &durations, test_unaligned_avx512_i32be , "test_unaligned_avx512_i32be")

  fmt.println("Second run")
  run_test(bytes, &durations, test_unaligned_scalar_core_i32be, "test_unaligned_scalar_core_i32be")
  run_test(bytes, &durations, test_unaligned_scalar_i32be, "test_unaligned_scalar_i32be")
  run_test(bytes, &durations, test_unaligned_sse_i32be , "test_unaligned_sse_i32be")
  run_test(bytes, &durations, test_unaligned_avx_i32be , "test_unaligned_avx_i32be")
  run_test(bytes, &durations, test_unaligned_avx512_i32be , "test_unaligned_avx512_i32be")


  delete(bytes)
  delete(durations)

}
