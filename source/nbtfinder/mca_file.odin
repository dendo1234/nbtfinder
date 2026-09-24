package nbtfinder

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

Mca_Location :: distinct u32be

McaLocation_getLenghtAndOffset :: proc(mca_location_entry: Mca_Location) -> (sector_offset: u32, sector_lenght: u8) {
  sector_offset = u32(mca_location_entry >> 8)
  sector_lenght = u8(mca_location_entry & 0xff)
  return
}


MCA_File :: struct {
  header_location : [mca_chunk_count]Mca_Location,
  timestamp_header : [mca_chunk_count]u32,

  sectors : [][mca_sector_size]u8

}


Mca_readAndDecompressChunk :: proc(appstate : ^AppState , file : ^os.File, mca_loc : Mca_Location) {
  offset, sector_lenght := McaLocation_getLenghtAndOffset(mca_loc)

  byte_offset : i64 = i64(offset)*mca_sector_size
  byte_lenght := mca_sector_size*int(sector_lenght)

  chunk_data := make([]u8, byte_lenght)
  defer delete(chunk_data)
  {
    n, err := os.read_at(file, chunk_data, byte_offset)
    if err != os.ERROR_NONE {
      fmt.printfln("Error reading chunk data")
      return
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
      return
    }
  }

  nbt_bytes := bytes.buffer_to_bytes(&nbt_buffer)

  fmt.println("Scalar")
  nbt_decode_set_procedures(.Scalar, true)

  for i := 0; i < 5; i += 1 {
    timing : Timing_Info
    appstate.header, timing = nbt_decode(nbt_bytes)

    fmt.println(timing)
  }

  fmt.println(appstate.compute_method)
  nbt_decode_set_procedures(appstate.compute_method, true)
  for i := 0; i < 5; i += 1 {
    timing : Timing_Info
    appstate.header, timing = nbt_decode(nbt_bytes)

    fmt.println(timing)
  }
}

Mca_read :: proc(appstate : ^AppState, filename : string) {
  file, err := os.open(filename)
  defer os.close(file)
  if err != os.ERROR_NONE {
    fmt.printfln("Error opening file %s", err)
    return
  }

  sector : [mca_sector_size]u8

  mca : MCA_File
  n : int

  n, err = os.read(file, slice.to_bytes(mca.header_location[:]))
  if err != os.ERROR_NONE {
    fmt.printfln("Error reading 1st header on %s. Error: %s", filename, err)
    return
  }

  n, err = os.read(file, slice.to_bytes(mca.timestamp_header[:]))
  if err != os.ERROR_NONE {
    fmt.printfln("Error reading 2st header on %s. Error: %s", filename, err)
    return
  }

  for mca_loc in mca.header_location {
    if (mca_loc != 0) {
      Mca_readAndDecompressChunk(appstate, file, mca_loc)

      break
    }
  }
}

