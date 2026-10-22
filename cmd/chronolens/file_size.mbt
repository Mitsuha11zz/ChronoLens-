///|
#cfg(platform="windows")
priv struct CliPath(String)

///|
#cfg(not(platform="windows"))
priv struct CliPath(Bytes)

///|
#cfg(platform="windows")
fn make_cli_path(path : String) -> CliPath {
  CliPath(path)
}

///|
#cfg(not(platform="windows"))
fn make_cli_path(path : String) -> CliPath {
  CliPath(@unicode.to_utf8_bytes(path) + Bytes::make(1, (0).to_byte()))
}

///|
#borrow(path)
extern "C" fn file_size_ffi(path : CliPath) -> Int64 = "chronolens_input_file_size"

///|
fn input_file_size(path : String) -> Int64 {
  file_size_ffi(make_cli_path(path))
}
