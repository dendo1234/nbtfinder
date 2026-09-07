package nbtfinder

/*
Nbt_Values :: union {
  i8,
  i16be,
  i32be,
  i64be,
  f32be,
  f64be,
  []i8,
  string,
  struct {
    type : typeid
    data : []u8
  }
  []Nbt_Tag,
  []i32be,
  []i64be,
}
*/

Nbt_Tag :: struct {
  // NOTE(dendo): nameless Nbt_Tag have name == 0
  // TODO(dendo): Should we strees about storing nameless tags differently to save space?
  name : string,
  type : Nbt_TagType,
  value : Nbt_TagValue,
}

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

ArrayIndex :: distinct u32

LongIndex :: distinct ArrayIndex
DoubleIndex :: distinct ArrayIndex

// NOTE(dendo): index to (an array of views to) arrays of bytes
ByteViewIndex :: distinct ArrayIndex
IntViewIndex :: distinct ArrayIndex
LongViewIndex :: distinct ArrayIndex

Nbt_ListIndex :: distinct ArrayIndex
TagsViewIndex :: distinct ArrayIndex

Nbt_TagValue :: struct #raw_union {
  byte : i8,
  short : i16,
  integer : i32,
  long : LongIndex,
  float : f32,
  double : DoubleIndex,
  byte_array : ByteViewIndex,
  str : string,
  list : Nbt_ListIndex,
  compound : TagsViewIndex,
  int_array : IntViewIndex,
  long_array : LongViewIndex,
}

ArrayView :: struct {
  start_index : u32,
  count : u32
}

// NOTE: Nbt actualy doesn't support arrays with more than (2^31 - 1) elemments becuase of Java, so this is safe
BytesView :: distinct ArrayView
IntsView :: distinct ArrayView
LongsView :: distinct ArrayView
TagsView :: distinct ArrayView


Nbt_List :: union {
  []i8,
  []i16,
  []i32,
  []i64,
  []f32,
  []f64,
  [][]i8, // byte_array
  []string,

  // NOTE(dendo): this could be an ArrayView like, but it wouldn't save any data
  // NOTE(dendo): i hate this type, but ok
  []Nbt_List, // lists of lists

  []TagsView, // lists of compunds

  [][]i32, // int_array
  [][]i64, // long_array

}

Nbt_FileHeaderData :: struct {
  // NOTE: children are stored togheter
  tags : []Nbt_Tag,

  // NOTE(dendo): these bytes and ints reagions only contain bytes and ints from byte_arrays and int_arrays,
  // as the others are stored inplace in the Nbt_Tag structure
  bytes : []i8,
  ints : []i32,

  longs : []i64,
  doubles : []f64,

  bytes_views : []BytesView,
  ints_views : []IntsView,
  longs_views : []LongsView,

  // NOTE: points to tags
  childrens : []TagsView,

  lists : []Nbt_List,
}






















