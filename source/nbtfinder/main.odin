package nbtfinder

import "base:intrinsics"
import "core:bytes"
import "core:compress/zlib"
import "core:fmt"
import "core:io"
import "core:os"
import "core:slice"
import "core:strings"

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
  mu_context : mu.Context
}

init :: proc(appstate : ^AppState) -> (ok : bool) {

  mu.init(&appstate.mu_context)

  mu_context := &appstate.mu_context;
  mu_context.text_width  = mu.default_atlas_text_width
  mu_context.text_height = mu.default_atlas_text_height

  return true
}

render :: proc(appstate : ^AppState) -> (ret: ^mu.Context) {
  rect : mu.Rect = {
    x = 0, y = 0,
    w = window_specs.width, h = window_specs.height
  }
  ctx := &appstate.mu_context

  mu.begin(ctx)
  {
    mu.begin_window(ctx, window_specs.title, rect, )
    {
      if (mu.button(ctx, "test") == { mu.Result.ACTIVE }) {
        fmt.println("Button Press")
      }
    }
    mu.end_window(ctx)
  }
  mu.end(ctx)

  return ctx
}



mca_sector_size :: 4096
mca_chunk_count :: 1024

Pos2D :: struct {
  x : i32,
  z : i32
}

PosChunk :: distinct Pos2D
PosBlock :: distinct Pos2D
PosRegion :: distinct Pos2D

Nbt_TagType :: enum u8 {
  End       = 0x00,
  Byte      = 0x01,
  Short     = 0x02,
  Int       = 0x03,
  Long      = 0x04,
  Float     = 0x05,
  Double    = 0x06,
  ByteArray = 0x07,
  String    = 0x08,
  List      = 0x09,
  Compound  = 0x0A,
  IntArray  = 0x0B,
  LongArray = 0x0C,
}


Mca_Location :: distinct u32be

McaLocation_getLenghtAndOffset :: proc(mca_location_entry: Mca_Location) -> (offset: u32, lenght: u8) {
  offset = u32(mca_location_entry >> 8)
  lenght = u8(mca_location_entry & 0xff)
  return
}


Mca_File :: struct {
  header_location : [mca_chunk_count]Mca_Location,
  timestamp_header : [mca_chunk_count]u32,

  sectors : [][mca_sector_size]u8

}

Nbt_Reader :: struct {
  bytes : []u8,
  index : uint
}

Nbt_readField :: proc(reader : ^Nbt_Reader, $type : typeid) -> (ret : type) {
  assert(len(reader.bytes)-int(reader.index + size_of(type)) >= 0, "nbt passer failed")

  ret = intrinsics.unaligned_load(cast(^type)&reader.bytes[reader.index])
  reader.index += size_of(type)
  return
}

// NOTE: assumes lenght : u16be before the string itself
Nbt_readString :: proc(reader : ^Nbt_Reader) -> (ret : string) {
  string_lenght := Nbt_readField(reader, u16be)

  assert(len(reader.bytes)-int(reader.index + uint(string_lenght)) >= 0, "nbt passer failed")

  bytes_string := reader.bytes[reader.index:reader.index+uint(string_lenght)]
  // TODO(dendo): it seams a bit dumb to allocate a string for every field when most of the fields repeat the sames strings
  // maybe implement a hash table with "known strings" and store them that way
  str, err := strings.clone_from_bytes(bytes_string)
  if err != nil {
    fmt.printfln("\nError: %v", err)
  }

  assert(err == nil, "allocation failed")

  reader.index += uint(string_lenght)
  return str
}

Nbt_readArray :: proc(reader : ^Nbt_Reader, $type : typeid) {
  size := Nbt_readField(reader, u32be)
  for ; size > 0; size -= 1 {
    value := Nbt_readField(reader, type)
    fmt.print(value)
  }
  fmt.println()
}

Nbt_decode :: proc(nbt_bytes : []u8) {
  reader : Nbt_Reader = {
    bytes = nbt_bytes,
    index = 0
  }

  nested_compound_tags := 1

  for {
    // DESC: parsing root tag
    tag := Nbt_TagType(reader.bytes[reader.index])
    reader.index += 1

    if nested_compound_tags > 0 {
      // DESC: read key string after tag

      // NOTE(dendo): does every tag (apart from lists) has a string name?? it seams so but you can't be sure
      // minecraft.wiki says that only tags inside compound tags have names, but the root tag is always a compound tag
      // maybe on bedrock nbt this is not true?
      // regardless, bedrock nbt are LE instead of BE, so more work would be need to support it

      str := Nbt_readString(&reader)
      fmt.println(str)

    }

    // DESC: read payload
    switch tag {
      case .End:

      case .Byte:
        byte : i8 = i8(reader.bytes[reader.index])
        reader.index += 1

      case .Short:
        short := Nbt_readField(&reader, i16be)

      case .Int:
        integer := Nbt_readField(&reader, i32be)

      case .Long:
        long := Nbt_readField(&reader, i64be)

      case .Float:
        float := Nbt_readField(&reader, f32be)

      case .Double:
        double := Nbt_readField(&reader, f64be)

      case .ByteArray:
        Nbt_readArray(&reader, i8)

      case .String:
        str := Nbt_readString(&reader)
        fmt.println(str)

      case .List:

      case .Compound:

      case .IntArray:
        Nbt_readArray(&reader, i32be)

      case .LongArray:
        Nbt_readArray(&reader, i64be)

    }
  }
}

Mca_readAndDecompressChunk :: proc(file : ^os.File, mca_loc : Mca_Location) {
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

  Nbt_decode(nbt_bytes)

}

Mca_read :: proc(filename : string) {
  file, err := os.open(filename)
  defer os.close(file)
  if err != os.ERROR_NONE {
    fmt.printfln("Error opening file %s", err)
    return
  }


  sector : [mca_sector_size]u8

  mca : Mca_File
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
      Mca_readAndDecompressChunk(file, mca_loc)

      break
    }
  }


}

