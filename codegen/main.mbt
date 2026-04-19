fn run() -> Unit raise {
  let output_path = "parsergen/generated-parser.mbt"
  let output = generate_parser_source()
  @fs.write_string_to_file(output_path, output)
  println(output)
}

fn main {
  run() catch {
    err => abort("\{err}")
  }
}
