fn run() -> Unit raise {
  for spec in parser_specs() {
    let output_path = "parsergen/\{spec.file_stem}_parser.mbt"
    let output = generate_parser_source(spec)
    @fs.write_string_to_file(output_path, output)
    println(output_path)
  }
}

fn main {
  run() catch {
    err => abort("\{err}")
  }
}
