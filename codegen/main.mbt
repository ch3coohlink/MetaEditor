struct Item {
  name : String
  done : Bool
} derive(FromJson)

struct Input {
  module_name : String
  title : String
  enabled : Bool
  count : Int
  items : Array[Item]
} derive(FromJson)

fn bool_lit(v : Bool) -> String {
  if v { "true" } else { "false" }
}

fn item_lit(item : Item) -> String {
  "{ name: \{item.name.to_json().stringify()}, done: \{bool_lit(item.done)} }"
}

fn generate(input : Input) -> String {
  let items = input.items.map(item_lit).iter().join(",\n  ")
  [
    "struct Todo {",
    "  name : String",
    "  done : Bool",
    "}",
    "",
    "let module_name = \{input.module_name.to_json().stringify()}",
    "let title = \{input.title.to_json().stringify()}",
    "let enabled = \{bool_lit(input.enabled)}",
    "let count = \{input.count}",
    "let todos : Array[Todo] = [",
    "  \{items}",
    "]",
    "",
  ].iter().join("\n")
}

fn read_input(path : String) -> Input raise {
  @json.from_json(@json.parse(@fs.read_file_to_string(path)))
}

fn run() -> Unit raise {
  let input_path = "input.json"
  let output_path = "generated.mbt.txt"
  let output = generate(read_input(input_path))
  @fs.write_string_to_file(output_path, output)
  println(output)
}

fn main {
  run() catch {
    err => abort("\{err}")
  }
}
