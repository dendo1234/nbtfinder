package nbtfinder

import "base:intrinsics"
import "base:runtime"
import "core:bytes"
import "core:compress"
import "core:compress/gzip"
import "core:compress/zlib"
import "core:flags"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:simd"
import "core:time"
import win "core:sys/windows"

find_first :: find_first_naive_simd
count_all :: count_all_naive_simd

Search_Type :: enum {
	find_first,
	count_all
}

Search_Arguments :: struct {
	filename: string         `args:"pos=0" usage:"Input file"                   `,
	pattern: string          `args:"pos=1" usage:"String pattern to be searched"`,
	search_type: Search_Type `args:"pos=2" usage:"find_first or count_all"      `
}

main :: proc () {
  // NOTE(dendo): prety lazy fix to make windows tolerate utf8 on the terminal
  {
    when ODIN_OS == .Windows {
      win.SetConsoleOutputCP(win.CODEPAGE.UTF8)
    }
  }


	options: Search_Arguments

  if len(os.args) > 2 {
    flags.parse_or_exit(&options, os.args)
  } else {
		flags.write_usage(os.to_stream(os.stdout), Search_Arguments)
	}

	search_procedure : type_of(find_first)
	switch options.search_type {
		case .find_first:
			search_procedure = find_first
		case .count_all:
			search_procedure = count_all

	}

	//runtime.debug_trap()

	result, performance, err := search_filename(options.filename, options.pattern, search_procedure)
	if err != nil {
		fmt.println(err)
	} else {
		search_result_print(options.filename, result)
	}
}

tests :: proc() {
	{
		gm := Find_Result_Compressed_NBT{ 2910316 }

		result, performance, err := search_filename("2-level.dat", "1.20.1-1.3.3", find_first)
		assert(err == nil)

		performance_data_print(performance)

		assert(result.(Find_Result_Compressed_NBT) == gm)
	}

	/*
	{
		gm1 := 757
		gm2 := 33582
		tick := time.tick_now()

		dut1, dut2, err := find_first_mca("r.0.0.mca", "greate:large_andesite_alloy_cogwheel", find_first)
		assert(err == nil)

		duration := time.tick_since(tick)

		fmt.println(duration)

		assert(dut1 == gm1)
		assert(dut2 == gm2)
	}
	*/
}

File_Type :: enum {
	UNKOWN,
	GZIP,
	MCA,
}

guess_file_type :: proc (filename: string) -> File_Type {
  if len(filename) < 5 {
    return nil
  }

  if filename[len(filename)-4:] == ".mca" {
    return .MCA
  }
  
  if len(filename) >= 9 && filename[len(filename)-9:] == "level.dat" {
    return .GZIP
  }

	return nil
}

/*==============================================================================
** file searching
*/

Aligned_Allocator_Data :: struct {
	backing_allocator: runtime.Allocator,
	alignment: int
}

aligned_allocator_proc :: proc(
	allocator_data: rawptr,
	mode:           runtime.Allocator_Mode,
	size:           int,
	alignment:      int,
	old_memory:     rawptr,
	old_size:       int,
	loc := #caller_location,
) -> ([]byte, runtime.Allocator_Error)  {
	data := (^Aligned_Allocator_Data)(allocator_data)

	return data.backing_allocator.procedure(
		data.backing_allocator.data,
		mode,
		size,
		data.alignment,
		old_memory,
		old_size,
		loc
	)
}

Aligned_Allocator :: proc(data: ^Aligned_Allocator_Data) -> runtime.Allocator {
	return runtime.Allocator{
		procedure = aligned_allocator_proc,
		data = data
	}
}

Find_Result_Compressed_NBT:: struct {
	byte_index: int
}

Find_Result_MCA:: struct {
	byte_index: int,
	chunk_index: int
}

Search_Result :: union {
	Find_Result_Compressed_NBT,
	Find_Result_MCA,
	Count_Result,
}

search_result_print :: proc(filename: string, result: Search_Result) {
	switch type in result {
		case Find_Result_Compressed_NBT:
			fmt.printfln("Found at %v, byte_index: $v", filename, type.byte_index)
		case Find_Result_MCA:
			file_chunk_x := type.chunk_index % 32
			file_chunk_z := type.chunk_index / 32
			region_x, region_z := mca_filename_get_region(filename)

			world_coordinate_x := region_x*512 + file_chunk_x*16
			world_coordinate_z := region_z*512 + file_chunk_z*16
			fmt.printfln("Found at %v, File: [chunk_index: %v (%v, %v), byte_index: %v], Chunk world coord: (%v, %v)",
				filename,
				type.chunk_index, file_chunk_x, file_chunk_z, type.byte_index,
				world_coordinate_x, world_coordinate_z
				)
		case Count_Result:
			fmt.printfln("Found at %v, count: %v", filename, type.amount)
	}
}

NBTFinder_Error :: enum {
	File_Type_Not_Known,
	File_Empty,
	File_Invalid,
	File_Unsuported,

	Not_Found,
}

Error :: union {
	os.Error,
	gzip.Error,
	MCA_Search_Error,
	NBTFinder_Error,
}

Performance_Data :: struct {
	duration: time.Duration,
	uncompressed_bytes_proccessed : int,
	compressed_bytes_proccessed : int,
}

performance_data_print :: proc (performance: Performance_Data) {
	compressed_speed := int((f64(performance.compressed_bytes_proccessed)/f64(performance.duration))*1e9)
	uncompressed_speed := int((f64(performance.uncompressed_bytes_proccessed)/f64(performance.duration))*1e9)
	fmt.printfln("Proccessed (total|speed): compressed:%M|%M/s, uncompressed:%M|%M/s, time:%v",
		performance.compressed_bytes_proccessed, compressed_speed,
		performance.uncompressed_bytes_proccessed, uncompressed_speed,
		performance.duration
	)
}

performance_data_add :: proc (lhs, rhs: Performance_Data) -> (res: Performance_Data) {
	return {
		duration                      = lhs.duration + rhs.duration,
		uncompressed_bytes_proccessed = lhs.uncompressed_bytes_proccessed + rhs.uncompressed_bytes_proccessed,
		compressed_bytes_proccessed   = lhs.compressed_bytes_proccessed + rhs.compressed_bytes_proccessed
	}
}

search_filename :: proc (filename, pattern: string, search_procedure: proc ([]byte, string) -> Search_Procedure_Result) -> (result: Search_Result, performance: Performance_Data, err: Error) {
	file_type := guess_file_type(filename)

	if file_type == nil {
		return nil, {}, NBTFinder_Error.File_Type_Not_Known
	}

	file_bytes := os.read_entire_file_from_path(filename, context.temp_allocator) or_return
	if len(file_bytes) == 0 {
		return nil, {}, NBTFinder_Error.File_Empty
	}

	uncompressed_bytes_proccessed: int
	tick := time.tick_now()
	switch file_type {
		case .GZIP:
			result, uncompressed_bytes_proccessed = search_compressed_nbt(file_bytes, pattern, search_procedure) or_return
		case .MCA:
			result, uncompressed_bytes_proccessed = search_mca(file_bytes, pattern, search_procedure) or_return
		case .UNKOWN:
			unreachable()
	}

	duration := time.tick_since(tick)

	performance.compressed_bytes_proccessed = len(file_bytes)
	performance.uncompressed_bytes_proccessed = uncompressed_bytes_proccessed

	free_all(context.temp_allocator)
	return
}

search_compressed_nbt :: proc (
	file_bytes: []u8,
	pattern: string,
	search_procedure: proc ([]byte, string) -> Search_Procedure_Result
	) -> (result: Search_Result, uncompressed_bytes_proccessed: int, err: gzip.Error)
{
	aligned_allocator_data := new(Aligned_Allocator_Data)
	defer free(aligned_allocator_data)
	aligned_allocator_data.backing_allocator = context.temp_allocator
	aligned_allocator_data.alignment = 64

	aligned_allocator := Aligned_Allocator(aligned_allocator_data)

	uncompressed_buffer : bytes.Buffer
	bytes.buffer_init_allocator(&uncompressed_buffer, 0, 64, aligned_allocator)
	defer bytes.buffer_destroy(&uncompressed_buffer)

	// NOTE(dendo): this gzip call asks for an allocator,
	// but it doesn't allocates anything since the data comes from memory
	gzip.load_from_bytes(file_bytes, &uncompressed_buffer, len(file_bytes), -1, context.allocator) or_return

	nbt_bytes := bytes.buffer_to_bytes(&uncompressed_buffer)
	uncompressed_bytes_proccessed = len(nbt_bytes)

	search_result := search_procedure(nbt_bytes, pattern)

	switch type in search_result {
		case Count_Result:
			result = type
		case Find_Result:
			result = Find_Result_Compressed_NBT{type.byte_index}
			uncompressed_bytes_proccessed = type.byte_index
	}

	return
}

@(private="file")
MCA_Location :: distinct u32be
MCA_CHUNK_COUNT :: 1024
MCA_SECTOR_SIZE :: 4096

MCA_Location_parse :: proc(mca_location_entry: MCA_Location) -> (sector_offset: u32, sector_lenght: u8) {
  sector_offset = u32(mca_location_entry >> 8)
  sector_lenght = u8(mca_location_entry & 0xff)
  return
}

mca_filename_get_region :: proc (filename: string) -> (region_x: int, region_z: int) {
	// r.x.z.mcr
	size := len(filename)
	assert(size >= 9)

	assert(filename[size-4:] == ".mcr" || filename[size-4:] == ".mca")

	index := 0
	start_x, start_z, end_x, end_z: int
	for ; index < size - 1; index += 1 {
		if filename[index:index+2] == "r." {
			index += 2
			start_x = index
			break;
		}
	}

	for ; index < size; index += 1 {
		if filename[index] == '.' {
			end_x = index
			index += 1
			start_z = index
			break;
		}
	}

	for ; index < size; index += 1 {
		if filename[index] == '.' {
			end_z = index
			break;
		}
	}

	assert(filename[index:index+4] == ".mcr" || filename[index:index+4] == ".mca")

	atoi :: proc(str: string) -> int {
		multiplier := 1
		index := 0
		if str[index] == '-' {
			multiplier = -1
			index += 1
		}

		result := 0
		for ; index < len(str); index += 1 {
			result *= 10
			result += int(str[index] - '0')
		}
		return result*multiplier
	}

	x := atoi(filename[start_x:end_x])
	z := atoi(filename[start_z:end_z])

	return x, z
}

@(private="file")
MCA_File_Header :: struct {
  location: [MCA_CHUNK_COUNT]MCA_Location,
  timestamp_header: [MCA_CHUNK_COUNT]u32,
}

MCA_Search_Error :: union {
	os.Error,
	zlib.Error,
	runtime.Allocator_Error,
	NBTFinder_Error
}

MCA_Chunk_Compression_Type :: enum i8 {
	GZip         = 1,
	Zlib         = 2,
	Uncompressed = 3,
	LZ4          = 4,
	Custom       = 127,
}

search_mca :: proc (
	file_bytes: []u8,
	pattern: string,
	search_procedure: proc ([]byte, string) -> Search_Procedure_Result
	) -> (result: Search_Result, uncompressed_bytes_proccessed: int, err: MCA_Search_Error)
{
	if len(file_bytes) <= size_of(MCA_File_Header) {
		return nil, 0, NBTFinder_Error.File_Invalid
	}
	
  mca_header: ^MCA_File_Header = (^MCA_File_Header)(raw_data(file_bytes[0:8196]))

	aligned_allocator_data := new(Aligned_Allocator_Data)
	defer free(aligned_allocator_data)
	aligned_allocator_data.backing_allocator = context.temp_allocator
	aligned_allocator_data.alignment = 64

	aligned_allocator := Aligned_Allocator(aligned_allocator_data)

	uncompressed_buffer : bytes.Buffer
	bytes.buffer_init_allocator(&uncompressed_buffer, 0, 64, aligned_allocator)
	defer bytes.buffer_destroy(&uncompressed_buffer)

	count := 0
	uncompressed_bytes_proccessed = 0
	for chunk_index in 0..<MCA_CHUNK_COUNT {
		location := mca_header.location[chunk_index]
		if (location != 0) {
			offset, lenght_sectors := MCA_Location_parse(location)

			base := int(offset)*MCA_SECTOR_SIZE
			top := base+int(lenght_sectors)*MCA_SECTOR_SIZE
			chunk := file_bytes[base:top]

			lenght_bytes := u32(slice.reinterpret([]u32be, chunk)[0])
			compression_type := slice.reinterpret([]MCA_Chunk_Compression_Type, chunk)[4]

			buf: []u8
			switch compression_type {
				case .Zlib:
					chunk_data : []u8 = chunk[5:5+lenght_bytes-1]

					zlib.inflate(input=chunk_data, buf=&uncompressed_buffer) or_return
					buf = bytes.buffer_to_bytes(&uncompressed_buffer)
				case .GZip:
					// never tested this
					chunk_data : []u8 = chunk[5:5+lenght_bytes-1]

					gzip.load_from_bytes(file_bytes, &uncompressed_buffer, len(file_bytes), -1, context.allocator) or_return
					buf = bytes.buffer_to_bytes(&uncompressed_buffer)
				case .Uncompressed:
					// never tested this
					chunk_data : []u8 = chunk[5:5+lenght_bytes-1]

					buf = chunk_data
				case .LZ4, .Custom:
					return nil, 0, NBTFinder_Error.File_Unsuported
				case:
					return nil, 0, NBTFinder_Error.File_Invalid
			}

			search_result := search_procedure(buf, pattern)
			switch type in search_result {
				case Find_Result:
					if type.byte_index != -1 {
						uncompressed_bytes_proccessed += type.byte_index
						result = Find_Result_MCA{ chunk_index = chunk_index, byte_index = type.byte_index}
						break
					}
					uncompressed_bytes_proccessed += len(buf)
				case Count_Result:
					count += type.amount
					uncompressed_bytes_proccessed += len(buf)
					result = Count_Result{count}
					break
			}

			bytes.buffer_reset(&uncompressed_buffer)
		}
	}

	if result == nil {
		err = NBTFinder_Error.Not_Found

	}


	return
}


/*==============================================================================
** search procedures
*/

Count_Result :: struct {
	amount: int
}

Find_Result :: struct {
	byte_index: int
}

Search_Procedure_Result :: union {
	Count_Result,
	Find_Result
}

find_first_naive_simd :: proc (buf: []u8, str: string) -> (result: Search_Procedure_Result) {
	string_compare :: proc (buf: []u8, str: string) -> bool {
		if len(buf) < len(str) {
			return false
		}

		for i in 0..<len(str) {
			if str[i] != buf[i] {
				return false
			}
		}
		return true
	}

	assert(len(str) > 0)
	assert(uintptr(raw_data(buf)) % 64 == 0) // is aligned

	start_char := str[0]

  compare : #simd[64]u8 = start_char

	index := 0
	offset := int(uintptr(raw_data(buf)) % uintptr(64))

	for ; index < len(buf); index += 64 {
		//data := intrinsics.unaligned_load( (^#simd[64]u8)(&buf[index]) )
		data := (^#simd[64]u8)(&buf[index])^
		result := simd.lanes_eq(compare, data)

		check := simd.extract_lsbs(result)

		jndex := 0
		for eq in check {
			if eq != 0 {
				if string_compare(buf[index + eq:], str) {
					return Find_Result{ index + eq }
				}
			}
		}
	}
	return Find_Result{ -1 }
}

count_all_naive_simd :: proc(buf: []byte, str: string) -> (result: Search_Procedure_Result) {
	string_compare :: proc (buf: []u8, str: string) -> bool {
		if len(buf) < len(str) {
			return false
		}

		for i in 0..<len(str) {
			if str[i] != buf[i] {
				return false
			}
		}
		return true
	}

	assert(len(str) > 0)
	assert(uintptr(raw_data(buf)) % 64 == 0) // is aligned

	start_char := str[0]

  compare : #simd[64]u8 = start_char

	index := 0
	offset := int(uintptr(raw_data(buf)) % uintptr(64))

	count := 0
	for ; index < len(buf); index += 64 {
		//data := intrinsics.unaligned_load( (^#simd[64]u8)(&buf[index]) )
		data := (^#simd[64]u8)(&buf[index])^
		result := simd.lanes_eq(compare, data)

		check := simd.extract_lsbs(result)

		jndex := 0
		for eq in check {
			if eq != 0 {
				if string_compare(buf[index + eq:], str) {
					count += 1
				}
			}
		}
	}
	return Count_Result{ count }
}








