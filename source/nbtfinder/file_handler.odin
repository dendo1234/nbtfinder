package nbtfinder

import "core:strings"
import "core:path/filepath"

File_Store :: struct {
  nbt_decoded_cache: [16]NBT_Decoded_Cache_Entry,
  staged_files: [dynamic]Staged_File,
}

Staged_File :: struct {
  file_path: string,
  filename: string,
  cached_entry: ^NBT_Decoded_Cache_Entry // 0 = not available
}

NBT_Decoded_Cache_Entry :: struct {
  header: ^NBT_Decoded_Header,
  last_used: int
}

NBT_File_Type :: enum {
  UNKNOWN,
  MCA,
  GZIP,
}

file_type_guess :: proc(filename: string) -> NBT_File_Type {

  if len(filename) < 5 {
    return .UNKNOWN
  }

  if filename[len(filename)-4:] == ".mca" {
    return .MCA
  }
  
  if filename == "level.dat" {
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
      cached_entry = nil
    }

    append(&(file_store.staged_files), staged_file)
  }
}

open_file :: proc(appstate: ^AppState, staged_file_index: int) {
  file_path := appstate.file_store.staged_files[staged_file_index].filename

  file_type := file_type_guess(file_path)

  switch file_type {
    case .UNKNOWN:
      assert(false)
    case .MCA:
      Mca_read(appstate, file_path)
    case .GZIP:
      assert(false)

  }
}


