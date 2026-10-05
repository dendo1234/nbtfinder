package nbtfinder

import "core:bytes"
import "core:compress/gzip"
import "core:strings"
import "core:path/filepath"

File_Store :: struct {
  file_handler_cache: [16]File_Handler,
  staged_files: [dynamic]Staged_File,
}

NBT_File_Type :: enum {
  UNKNOWN,
  MCA,
  GZIP,
}

Staged_File :: struct {
  file_path: string,
  filename: string,
  cached_entry: ^File_Handler, // nil = not available
  type: NBT_File_Type
}

File_Handler :: struct {
  data : union {
   ^NBT_Decoded_Header,
   MCA_File_Header
  },
  last_used: int,
  staged_file_index: int
}

file_type_guess :: proc(filename: string) -> NBT_File_Type {
  if len(filename) < 5 {
    return .UNKNOWN
  }

  if filename[len(filename)-4:] == ".mca" {
    return .MCA
  }
  
  if len(filename) >= 9 && filename[len(filename)-9:] == "level.dat" {
    return .GZIP
  }

  return .UNKNOWN
}

/*
cache_add :: proc(cache: []NBT_Decoded_Cache_Entry) -> (slot: int){
  for i := 0; i < len(cache); i += 1 {
    if cache[i] == nil {

    }
  }
}
*/

init_file_store :: proc(appstate: ^AppState) {
  appstate.file_store.staged_files = make([dynamic]Staged_File, 0, 1)
}

stage_files :: proc(appstate: ^AppState, file_list: [^]cstring) {
  file_store := &appstate.file_store
  clear(&file_store.staged_files)

  for file_index := 0; file_list[file_index] != nil; file_index += 1 {
    file_path := strings.clone_from_cstring(file_list[file_index])

    filename: string
    for i := len(file_path)-1; i >= 0; i -= 1 {
      if file_path[i] == filepath.SEPARATOR {
        filename = file_path[i+1:]
        break;
      }
    }

    staged_file : Staged_File = {
      file_path = file_path,
      filename = filename,
      cached_entry = nil,
      type = file_type_guess(file_path)
    }

    append(&(file_store.staged_files), staged_file)
  }
}

gzip_read_Error :: union {
  gzip.Error
}

gzip_read :: proc(file_path: string) -> (handler: ^NBT_Decoded_Header, err: gzip_read_Error) {
  buf: bytes.Buffer
  gzip.load_from_file(file_path, &buf, -1, context.temp_allocator) or_return

  header, _ := nbt_decode(buf.buf[:])
  return header, {}
}

open_file_Error :: union {
  gzip_read_Error
}

get_file :: proc(appstate: ^AppState, staged_file_index: int) -> (handle: ^File_Handler) {
  return appstate.file_store.staged_files[staged_file_index].cached_entry
}

get_or_open_file :: proc(appstate: ^AppState, staged_file_index: int) -> (handler: ^File_Handler, err: open_file_Error) {
  cached := appstate.file_store.staged_files[staged_file_index].cached_entry
  if cached != nil {
    return cached, {}
  }


  return open_file(appstate, staged_file_index)
}

open_file :: proc(appstate: ^AppState, staged_file_index: int) -> (handler: ^File_Handler, err: open_file_Error) {
  file_path := appstate.file_store.staged_files[staged_file_index].file_path

  file_type := file_type_guess(file_path)

  new_handler: File_Handler
  new_handler.staged_file_index = staged_file_index

  switch file_type {
    case .UNKNOWN:
      assert(false)
    case .MCA:
      new_handler.data, _ = MCA_read(appstate, file_path)
    case .GZIP:
      new_handler.data = gzip_read(file_path) or_return
  }

  for &file_handler in appstate.file_store.file_handler_cache {
    if file_handler.data == nil {
      file_handler = new_handler

      appstate.file_store.staged_files[staged_file_index].cached_entry = &file_handler
      return &file_handler, {};
    }
  }

  assert(false)
  return nil, {}
}

close_file :: proc(appstate: ^AppState, staged_file_index: int) {
  appstate.file_store.staged_files[staged_file_index].cached_entry = nil
}


