package nbtfinder

import "base:runtime"
import "base:intrinsics"
import "core:time"
import "core:mem"
import "core:math"
import "core:fmt"
import "core:encoding/endian"


TEST_REPEAT_COUNT :: 32
STRIDE_COUNT :: 16

@(optimization_mode="favor_size")
test_unaligned_scalar_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
  type :: i32
  when type == i32 {
    type_to_load :: i32be
  } else when type == i64 {
    type_to_load :: i64be
  }
  
  when type == i32 {
    get_func :: endian.unchecked_get_u32be
  } else when type == i64 {
    get_func :: endian.unchecked_get_u64be
  }

  acc : type
  size := len(bytes) - size_of(type)
  // NOTE(dendo): warm the cache
  for index := 0; index < size; index += size_of(type) {
    acc += intrinsics.unaligned_load(cast(^type)&bytes[index])
  }
 

  for offset := 0; offset < STRIDE_COUNT; offset += 1 {
    tick := time.tick_now()
    //tick := intrinsics.read_cycle_counter()

    for index := offset; index < size; index += size_of(type) {

      //acc += type(get_func(bytes[index:]))
      acc += type(intrinsics.unaligned_load(cast(^type_to_load)&bytes[index]))

    }

    /*
    toc := intrinsics.read_cycle_counter()
    start := time.from_nanoseconds(tick)
    end := time.from_nanoseconds(toc)
    duration := time.diff(start, end)
    */

    duration := time.tick_since(tick)

    durations[offset] = duration;
  }


  return int(acc)
}

test_unaligned_scalar_core_i32be :: proc(bytes: []u8, durations: []time.Duration) -> int {
  type :: i32
  when type == i32 {
    get_func :: endian.unchecked_get_u32be
  } else when type == i64 {
    get_func :: endian.unchecked_get_u64be
  }

  acc : type
  size := len(bytes) - size_of(type)
  // NOTE(dendo): warm the cache
  for index := 0; index < size; index += size_of(type) {
    acc += intrinsics.unaligned_load(cast(^type)&bytes[index])
  }

  for offset := 0; offset < STRIDE_COUNT; offset += 1 {
    tick := time.tick_now()
    //tick := intrinsics.read_cycle_counter()

    for index := offset; index < size; index += size_of(type) {

      acc += type(get_func(bytes[index:]))

    }

    /*
    toc := intrinsics.read_cycle_counter()
    start := time.from_nanoseconds(tick)
    end := time.from_nanoseconds(toc)
    duration := time.diff(start, end)
    */

    duration := time.tick_since(tick)

    durations[offset] = duration;
  }

  return int(acc)
}

statistics_from_durations :: proc(durations: []time.Duration) -> (avg: time.Duration, std_deviation: time.Duration) {
  size := len(durations)

  for i := 0; i < size; i += 1 {
    avg += durations[i]/time.Duration(size)
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
) -> (avg: time.Duration, std_deviation: time.Duration) {

  resize(durations, repetition_count * STRIDE_COUNT)

  result : int = 0
  for i := 0; i < repetition_count; i += 1 {
    result += test_proc(bytes, durations[i*16:i*16+16])
  }
  avg, std_deviation = statistics_from_durations(durations[:])
  fmt.printfln("%40v - result: %v, avg: %v, std_deviation: %v", name, result, avg, std_deviation)

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

  fmt.println("Second run")
  run_test(bytes, &durations, test_unaligned_scalar_core_i32be, "test_unaligned_scalar_core_i32be")
  run_test(bytes, &durations, test_unaligned_scalar_i32be, "test_unaligned_scalar_i32be")

  fmt.println("Third run")
  run_test(bytes, &durations, test_unaligned_scalar_core_i32be, "test_unaligned_scalar_core_i32be")
  run_test(bytes, &durations, test_unaligned_scalar_i32be, "test_unaligned_scalar_i32be")

  fmt.println("fourth run")
  run_test(bytes, &durations, test_unaligned_scalar_core_i32be, "test_unaligned_scalar_core_i32be")
  run_test(bytes, &durations, test_unaligned_scalar_i32be, "test_unaligned_scalar_i32be")


  delete(bytes)
  delete(durations)

}
