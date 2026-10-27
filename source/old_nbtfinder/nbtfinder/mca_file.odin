package nbtfinder

import "base:runtime"
import "core:bytes"
import "core:compress/zlib"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

mca_sector_size :: 4096
mca_chunk_count :: 1024

Pos2D :: struct {
  x : i32,
  z : i32
}

PosChunk :: distinct Pos2D
PosBlock :: distinct Pos2D
PosRegion :: distinct Pos2D

MCA_Location :: distinct u32be

McaLocation_getLenghtAndOffset :: proc(mca_location_entry: MCA_Location) -> (sector_offset: u32, sector_lenght: u8) {
  sector_offset = u32(mca_location_entry >> 8)
  sector_lenght = u8(mca_location_entry & 0xff)
  return
}

mca_max_chunk_lenght :: 255
mca_max_sector_count :: mca_max_chunk_lenght * mca_chunk_count

// NOTE(dendo): Should we cast the mca file on disk to a struct or slice it up with pointers?
// for now I've went with the slice aprouch,

MCA_File_Header :: struct {
  raw_data: []u8,
  location: []MCA_Location,
  timestamp_header: []u32,
 
  sectors: [][mca_sector_size]u8
}

/*
MCA_File :: struct {
  header_location : [mca_chunk_count]MCA_Location,
  timestamp_header : [mca_chunk_count]u32,

  // HACK(dendo): odin doesn't have flexible array member feature. So this is an workaround.
  // Because of this, this structure is not meant to be instatiated, only casted.
  // If instatiated, it would have around 1 GiB!
  // also, odin's automatic bounds checks are useless here.
  sectors : [mca_max_sector_count][mca_sector_size]u8
}
*/


Mca_readAndDecompressChunk :: proc(appstate : ^AppState , file : ^os.File, mca_loc : MCA_Location) -> ^NBT_Decoded_Header {
  offset, sector_lenght := McaLocation_getLenghtAndOffset(mca_loc)

  byte_offset : i64 = i64(offset)*mca_sector_size
  byte_lenght := mca_sector_size*int(sector_lenght)

  chunk_data := make([]u8, byte_lenght)
  defer delete(chunk_data)
  {
    n, err := os.read_at(file, chunk_data, byte_offset)
    if err != os.ERROR_NONE {
      fmt.printfln("Error reading chunk data")
      return nil
    }
    assert(n != 0 && n%mca_sector_size == 0, "currupt mca file")
  }

  lenght := slice.reinterpret([]u32be, chunk_data)[0]
  compression_type := slice.reinterpret([]u8, chunk_data)[4]

  chunk_bytes : []u8 = chunk_data[5:4+lenght]
  nbt_buffer : bytes.Buffer
  defer bytes.buffer_destroy(&nbt_buffer)
  {
    err := zlib.inflate(input=chunk_bytes, buf=&nbt_buffer)

    if err != nil {
      fmt.printfln("\nError: %v", err)
      return nil
    }
  }

  nbt_bytes := bytes.buffer_to_bytes(&nbt_buffer)

  timing: Timing_Info
  header: ^NBT_Decoded_Header
  header, timing = nbt_decode(nbt_bytes)

  fmt.println(timing)

  return header
}

MCA_read_Error :: union {
  os.Error
}

MCA_read :: proc(appstate : ^AppState, filename : string) -> (handler: MCA_File_Header, err: MCA_read_Error)  {
  file := os.open(filename) or_return
  defer os.close(file)

  file_size := os.file_size(file) or_return
  memory := runtime.mem_alloc(int(file_size), alignment = 4096, allocator = context.allocator) or_return
  bytes_read := os.read_full(file, memory) or_return
  assert(bytes_read == int(file_size))

  mca_header: MCA_File_Header

  mca_header.raw_data = memory
  mca_header.location = slice.reinterpret([]MCA_Location, memory[0:4096])
  mca_header.timestamp_header = slice.reinterpret([]u32, memory[4096:8192])
  mca_header.sectors = slice.reinterpret([][mca_sector_size]u8,memory[8192:])

  for mca_loc in mca_header.location {
    if (mca_loc != 0) {
      Mca_readAndDecompressChunk(appstate, file, mca_loc)

      break
    }
  }

  return mca_header, MCA_read_Error{}
}

