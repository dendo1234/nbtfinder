package nbtfinder

import uprof "../amduprof"
import "base:intrinsics"
import "base:runtime"
import b "core:bytes"
import "core:encoding/endian"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:slice"
import "core:simd"
import "core:time"
import "core:compress/gzip"

TEST_REPEAT_COUNT :: 1
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

test_unaligned_simd :: #force_inline proc(bytes: []u8, durations: []time.Duration, $type: typeid, $simd_type: typeid) -> int {
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

test_unaligned_simd128_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
  return test_unaligned_simd(bytes, durations, i32, #simd[4]i32)
}

when ODIN_ARCH == .amd64 {
  @(enable_target_feature="avx,avx2")
  test_unaligned_simd256_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
    return test_unaligned_simd(bytes, durations, i32, #simd[8]i32)
  }
} else {
  test_unaligned_simd256_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
    return test_unaligned_simd(bytes, durations, i32, #simd[8]i32)
  }
}

when ODIN_ARCH == .amd64 {
  @(enable_target_feature="avx512f,avx512bw,avx512vl,avx512dq")
  test_unaligned_simd512_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
    return test_unaligned_simd(bytes, durations, i32, #simd[16]i32)
  }
} else {
  test_unaligned_simd512_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
    return test_unaligned_simd(bytes, durations, i32, #simd[16]i32)
  }
}


Statistics :: struct {
  avg: time.Duration,
  p95: time.Duration,
  std_deviation: time.Duration
}

statistics_from_durations :: proc(durations: []time.Duration) -> Statistics {
  size := len(durations)

  avg : time.Duration = 0
  for i := 0; i < size; i += 1 {
    avg += durations[i]/time.Duration(size)
  }
  slice.reverse_sort(durations)

  count95 := size / 20

  p95 : time.Duration = 0
  for i := 0; i < count95; i += 1 {
    p95 += durations[i]/time.Duration(count95)
  }

  variance : f64 = 0
  for i := 0; i < size; i += 1 {
    deviation := f64(durations[i]) - f64(avg)
    variance += deviation*deviation
  }
  variance /= f64(size)
  std_deviation := time.Duration(math.sqrt(variance))

  return {avg, p95, std_deviation}
}

should_retry :: proc(statistics: Statistics) -> bool {
  relative_std_deviation : f64 = f64(statistics.std_deviation)/f64(statistics.avg)
  // NOTE(dendo): this is pretty arbritary
  return relative_std_deviation > 0.15
}

run_test :: proc(
  bytes: []u8,
  durations: ^[dynamic]time.Duration,
  test_proc: proc(bytes: []u8, durations: []time.Duration) -> int,
  name : string,
  repetition_count: int = TEST_REPEAT_COUNT
) -> Statistics {
  resize(durations, repetition_count * STRIDE_COUNT)

  statistics: Statistics
  for tries := 10; tries >= 0; tries -= 1 {

    result : int = 0
    for i := 0; i < repetition_count; i += 1 {
      result += test_proc(bytes, durations[i*STRIDE_COUNT:i*STRIDE_COUNT+STRIDE_COUNT])
    }
    statistics = statistics_from_durations(durations[:])
    relative_std_deviation : f64 = f64(statistics.std_deviation)/f64(statistics.avg)

    mib_per_sec := f64(len(bytes))*1e3/f64(statistics.avg)
    fmt.printfln("%40v - result: %v, %v, %v, %v MiB/s", name, result, statistics, relative_std_deviation, mib_per_sec)

    if !should_retry(statistics) {
      break
    }
  }

  return statistics
}

run_tests :: #force_no_inline proc(cpu_features: CPU_Features) -> (best: Compute_Methods) {
  MiB :: 1 << 20
  bytes, err := mem.alloc_bytes_non_zeroed(MiB, alignment = mem.DEFAULT_ALIGNMENT)
  durations, err2 := make([dynamic]time.Duration, 0, 16)

  assert(err == .None && err2 == .None)

  rand_gen := runtime.default_random_generator()
  ok := runtime.random_generator_read_bytes(rand_gen, bytes)

  assert(ok)

  statistics : [4]Statistics

  statistics[0] = run_test(bytes, &durations, test_unaligned_scalar_i32be, "test_unaligned_scalar_i32be")

  if .SIMD_128_bits in cpu_features {
    statistics[1] = run_test(bytes, &durations, test_unaligned_simd128_i32be, "test_unaligned_simd128_i32be")
  }

  if .SIMD_256_bits in cpu_features {
    statistics[2] = run_test(bytes, &durations, test_unaligned_simd256_i32be, "test_unaligned_simd256_i32be")
  }

  if .SIMD_512_bits in cpu_features {
    statistics[3] = run_test(bytes, &durations, test_unaligned_simd512_i32be, "test_unaligned_simd512_i32be")
  }

  best = .Scalar
  best_avg := statistics[0].avg

  if statistics[1].avg != 0 && statistics[1].avg < best_avg {
    best = .SIMD_128_bits
    best_avg = statistics[1].avg
  }

  if statistics[2].avg != 0 && statistics[2].avg < best_avg {
    best = .SIMD_256_bits
    best_avg = statistics[2].avg
  }

  if statistics[3].avg != 0 && statistics[3].avg < best_avg {
    best = .SIMD_512_bits
    best_avg = statistics[3].avg
  }

  delete(bytes)
  delete(durations)

  nbt_decode_set_procedures(best, true)
  {
    buf: b.Buffer
    err := gzip.load_from_file("level.dat", &buf, -1, context.temp_allocator)
    assert(err == nil)

    uprof.ProfileResume()
    header, timing := nbt_decode(buf.buf[:])
    uprof.ProfilePause()
    fmt.println(timing)

    free(header)
  }

  return best
}

