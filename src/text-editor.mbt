pub struct TextEditorData { lines: Cel[Array[String]] }

pub struct TextEditorSession {
  cursor_row: Cel[Int]
  cursor_col: Cel[Int]
  anchor_row: Cel[Int]
  anchor_col: Cel[Int]
  selecting: Cel[Bool]
  focused: Cel[Bool]
}

pub struct TextEditorActions { get_text: () -> String }
pub struct TextEditorSessionActions { set_text: (String) -> Unit }

let text_editor_char_width = 8
let text_editor_line_height = 20
let text_editor_gutter_width = 44
let editor_page: UIMeta = ui("editor", style=(
  #| & {
  #|   display:flex;
  #|   flex-direction:column;
  #|   width:100%;
  #|   height:100%;
  #|   min-height:240px;
  #|   overflow:hidden;
  #|   border:1px solid #d6dbe4;
  #|   border-radius:12px;
  #|   background:#f7f9fc;
  #|   font:14px/20px Consolas,"Courier New",monospace;
  #|   color:#142033;
  #| }
))
let editor_toolbar: UIMeta = ui("toolbar", style=(
  #| & {
  #|   display:flex;
  #|   align-items:center;
  #|   gap:10px;
  #|   padding:10px 12px;
  #|   border-bottom:1px solid #e1e6ee;
  #|   background:#ffffff;
  #| }
))
let editor_title: UIMeta = ui("title")
let editor_status: UIMeta = ui("status", style=(
  #| & {
  #|   color:#5a677a;
  #|   font-size:12px;
  #| }
))
let editor_content: UIMeta = ui("content", style=(
  #| & {
  #|   position:relative;
  #|   flex:1;
  #|   min-height:0;
  #|   overflow:auto;
  #|   padding:8px 0;
  #|   outline:none;
  #| }
))
let editor_line: UIMeta = ui("line", style=(
  #| & {
  #|   display:grid;
  #|   grid-template-columns:44px 1fr;
  #|   min-height:20px;
  #| }
))
let editor_num: UIMeta = ui("num", style=(
  #| & {
  #|   padding:0 8px 0 0;
  #|   color:#7d8796;
  #|   text-align:right;
  #|   user-select:none;
  #| }
))
let editor_text: UIMeta = ui("text", style=(
  #| & {
  #|   white-space:pre;
  #|   padding-right:12px;
  #| }
))
let editor_input: UIMeta = ui("input", style=(
  #| & {
  #|   position:absolute;
  #|   inset:auto auto 8px 8px;
  #|   width:1px;
  #|   height:1px;
  #|   opacity:0;
  #|   pointer-events:none;
  #| }
))

fn clamp(v: Int, lo: Int, hi: Int) -> Int {
  if v < lo { lo } else if v > hi { hi } else { v }
}

fn split_lines(text: String) -> Array[String] {
  let parts = []
  for part in text.split("\n") { parts.push(part.to_string()) }
  if parts.length() == 0 { [""] } else { parts }
}

fn join_lines(lines: Array[String]) -> String { lines.iter().join("\n") }

fn line_at(lines: Array[String], row: Int) -> String {
  if row >= 0 && row < lines.length() { lines[row] } else { "" }
}

fn line_len(lines: Array[String], row: Int) -> Int { line_at(lines, row).length() }

fn set_cursor(d: TextEditorData, s: TextEditorSession, row: Int, col: Int) -> Unit {
  let lines = d.lines.get()
  let row = clamp(row, 0, lines.length() - 1)
  s.cursor_row.set(row)
  s.cursor_col.set(clamp(col, 0, line_len(lines, row)))
}

fn collapse_selection(s: TextEditorSession) -> Unit {
  s.selecting.set(false)
  s.anchor_row.set(s.cursor_row.get())
  s.anchor_col.set(s.cursor_col.get())
}

fn has_selection(s: TextEditorSession) -> Bool {
  s.selecting.get() && (
    s.anchor_row.get() != s.cursor_row.get() ||
    s.anchor_col.get() != s.cursor_col.get()
  )
}

fn selection_range(s: TextEditorSession) -> (Int, Int, Int, Int)? {
  if !has_selection(s) { return None }
  let sr = s.anchor_row.get()
  let sc = s.anchor_col.get()
  let er = s.cursor_row.get()
  let ec = s.cursor_col.get()
  if sr < er || (sr == er && sc <= ec) {
    Some((sr, sc, er, ec))
  } else {
    Some((er, ec, sr, sc))
  }
}

fn replace_range(lines: Array[String], sr: Int, sc: Int, er: Int, ec: Int, text: String) -> Array[String] {
  let before = lines[sr][0:sc].to_string()
  let after = lines[er][ec:].to_string()
  let parts = split_lines(text)
  let next = []
  let mut i = 0
  while i < sr {
    next.push(lines[i])
    i = i + 1
  }
  if parts.length() == 1 {
    next.push(before + parts[0] + after)
  } else {
    next.push(before + parts[0])
    let mut j = 1
    while j + 1 < parts.length() {
      next.push(parts[j])
      j = j + 1
    }
    next.push(parts[parts.length() - 1] + after)
  }
  i = er + 1
  while i < lines.length() {
    next.push(lines[i])
    i = i + 1
  }
  if next.length() == 0 { [""] } else { next }
}

fn set_text_state(d: TextEditorData, s: TextEditorSession, text: String) -> Unit {
  d.lines.set(split_lines(text))
  set_cursor(d, s, 0, 0)
  collapse_selection(s)
}

fn insert_text(d: TextEditorData, s: TextEditorSession, text: String) -> Unit {
  let lines = d.lines.get()
  let (sr, sc, er, ec) = match selection_range(s) {
    Some(v) => v
    None => (s.cursor_row.get(), s.cursor_col.get(), s.cursor_row.get(), s.cursor_col.get())
  }
  let next = replace_range(lines, sr, sc, er, ec, text)
  let parts = split_lines(text)
  let row = sr + parts.length() - 1
  let col = if parts.length() == 1 { sc + parts[0].length() } else { parts[parts.length() - 1].length() }
  d.lines.set(next)
  set_cursor(d, s, row, col)
  collapse_selection(s)
}

fn delete_selection(d: TextEditorData, s: TextEditorSession) -> Bool {
  match selection_range(s) {
    Some((sr, sc, er, ec)) => {
      d.lines.set(replace_range(d.lines.get(), sr, sc, er, ec, ""))
      set_cursor(d, s, sr, sc)
      collapse_selection(s)
      true
    }
    None => false
  }
}

fn move_cursor(d: TextEditorData, s: TextEditorSession, row: Int, col: Int,
  select?: Bool = false) -> Unit {
  let old_row = s.cursor_row.get()
  let old_col = s.cursor_col.get()
  if select {
    if !s.selecting.get() {
      s.anchor_row.set(old_row)
      s.anchor_col.set(old_col)
      s.selecting.set(true)
    }
  } else {
    s.selecting.set(false)
  }
  set_cursor(d, s, row, col)
  if !select {
    s.anchor_row.set(s.cursor_row.get())
    s.anchor_col.set(s.cursor_col.get())
  }
}

fn move_left(d: TextEditorData, s: TextEditorSession, select: Bool) -> Unit {
  let row = s.cursor_row.get()
  let col = s.cursor_col.get()
  if col > 0 {
    move_cursor(d, s, row, col - 1, select=select)
  } else if row > 0 {
    move_cursor(d, s, row - 1, line_len(d.lines.get(), row - 1), select=select)
  }
}

fn move_right(d: TextEditorData, s: TextEditorSession, select: Bool) -> Unit {
  let row = s.cursor_row.get()
  let col = s.cursor_col.get()
  let lines = d.lines.get()
  let len = line_len(lines, row)
  if col < len {
    move_cursor(d, s, row, col + 1, select=select)
  } else if row + 1 < lines.length() {
    move_cursor(d, s, row + 1, 0, select=select)
  }
}

fn move_up(d: TextEditorData, s: TextEditorSession, select: Bool) -> Unit {
  let row = s.cursor_row.get()
  if row > 0 { move_cursor(d, s, row - 1, s.cursor_col.get(), select=select) }
}

fn move_down(d: TextEditorData, s: TextEditorSession, select: Bool) -> Unit {
  let lines = d.lines.get()
  let row = s.cursor_row.get()
  if row + 1 < lines.length() { move_cursor(d, s, row + 1, s.cursor_col.get(), select=select) }
}

fn delete_backward(d: TextEditorData, s: TextEditorSession) -> Unit {
  if delete_selection(d, s) { return }
  let row = s.cursor_row.get()
  let col = s.cursor_col.get()
  if col > 0 {
    d.lines.set(replace_range(d.lines.get(), row, col - 1, row, col, ""))
    set_cursor(d, s, row, col - 1)
    collapse_selection(s)
  } else if row > 0 {
    let prev = line_len(d.lines.get(), row - 1)
    d.lines.set(replace_range(d.lines.get(), row - 1, prev, row, 0, ""))
    set_cursor(d, s, row - 1, prev)
    collapse_selection(s)
  }
}

fn delete_forward(d: TextEditorData, s: TextEditorSession) -> Unit {
  if delete_selection(d, s) { return }
  let row = s.cursor_row.get()
  let col = s.cursor_col.get()
  let lines = d.lines.get()
  let len = line_len(lines, row)
  if col < len {
    d.lines.set(replace_range(lines, row, col, row, col + 1, ""))
    set_cursor(d, s, row, col)
    collapse_selection(s)
  } else if row + 1 < lines.length() {
    d.lines.set(replace_range(lines, row, col, row + 1, 0, ""))
    set_cursor(d, s, row, col)
    collapse_selection(s)
  }
}

fn select_all(d: TextEditorData, s: TextEditorSession) -> Unit {
  let lines = d.lines.get()
  s.anchor_row.set(0)
  s.anchor_col.set(0)
  s.selecting.set(true)
  set_cursor(d, s, lines.length() - 1, line_len(lines, lines.length() - 1))
}

fn point_to_cursor(d: TextEditorData, x: Int, y: Int) -> (Int, Int) {
  let lines = d.lines.get()
  let row = clamp(y / text_editor_line_height, 0, lines.length() - 1)
  let col = clamp((x - text_editor_gutter_width) / text_editor_char_width, 0, line_len(lines, row))
  (row, col)
}

fn pointer_set_cursor(d: TextEditorData, s: TextEditorSession, x: Int, y: Int, select: Bool) -> Unit {
  let (row, col) = point_to_cursor(d, x, y)
  move_cursor(d, s, row, col, select=select)
}

fn line_selection(d: TextEditorData, s: TextEditorSession, row: Int) -> (Int, Int)? {
  match selection_range(s) {
    Some((sr, sc, er, ec)) => {
      if row < sr || row > er { None }
      else if sr == er { Some((sc, ec)) }
      else if row == sr { Some((sc, line_len(d.lines.get(), row))) }
      else if row == er { Some((0, ec)) }
      else { Some((0, line_len(d.lines.get(), row))) }
    }
    None => None
  }
}

fn line_text_child(d: TextEditorData, s: TextEditorSession, row: Int) -> Child {
  let text = line_at(d.lines.get(), row)
  let cursor_row = s.cursor_row.get()
  let cursor_col = clamp(s.cursor_col.get(), 0, text.length())
  let focused = s.focused.get()
  let caret = h("span", [
    Style("display", Static(String("inline-block"))),
    Style("width", Static(String("0"))),
    Style("height", Static(String("16px"))),
    Style("margin", Static(String("2px 0"))),
    Style("border-left", Static(String("1px solid #1f3a5b"))),
    Style("vertical-align", Static(String("text-bottom"))),
  ], [])
  let selected = text => h("span", [
    Style("background", Static(String("#cfe2ff"))),
  ], [Str(text)])
  match line_selection(d, s, row) {
    Some((sc, ec)) => {
      let before = text[0:sc].to_string()
      let selected_text = text[sc:ec].to_string()
      let after = text[ec:].to_string()
      if focused && cursor_row == row && cursor_col == sc {
        Arr([
          caret,
          selected(selected_text),
          Str(after),
        ])
      } else if focused && cursor_row == row && cursor_col == ec {
        Arr([
          Str(before),
          selected(selected_text),
          caret,
          Str(after),
        ])
      } else {
        Arr([
          Str(before),
          selected(selected_text),
          Str(after),
        ])
      }
    }
    None => {
      if focused && cursor_row == row {
        Arr([
          Str(text[0:cursor_col].to_string()),
          caret,
          Str(text[cursor_col:].to_string()),
        ])
      } else {
        Str(text)
      }
    }
  }
}

fn editor_keydown(d: TextEditorData, s: TextEditorSession, ev: Event) -> Unit {
  match ev.data {
    Key(v) => {
      if !v.mod.ctrl && !v.mod.alt && !v.mod.meta && v.key.length() == 1 {
        insert_text(d, s, v.key)
        return
      }
      if v.mod.ctrl && v.key.to_upper() == "A" {
        select_all(d, s)
        return
      }
      match v.key {
        "ArrowLeft" => move_left(d, s, v.mod.shift)
        "ArrowRight" => move_right(d, s, v.mod.shift)
        "ArrowUp" => move_up(d, s, v.mod.shift)
        "ArrowDown" => move_down(d, s, v.mod.shift)
        "Home" => move_cursor(d, s, s.cursor_row.get(), 0, select=v.mod.shift)
        "End" => move_cursor(d, s, s.cursor_row.get(),
          line_len(d.lines.get(), s.cursor_row.get()), select=v.mod.shift)
        "Backspace" => delete_backward(d, s)
        "Delete" => delete_forward(d, s)
        "Enter" => insert_text(d, s, "\n")
        "Tab" => insert_text(d, s, "  ")
        _ => ()
      }
    }
    _ => ()
  }
}

pub let text_editor: Entry[TextEditorData, TextEditorSession, TextEditorActions, TextEditorSessionActions] = {
  id: "text-editor", title: "Text Editor",
  data: () => {{ lines: cel(split_lines("hello\nworld")) }},
  session: _ => {{
    cursor_row: cel(0),
    cursor_col: cel(0),
    anchor_row: cel(0),
    anchor_col: cel(0),
    selecting: cel(false),
    focused: cel(false),
  }},
  actions: (_, d) => {{
    get_text: () => join_lines(d.lines.get()),
  }},
  session_actions: (_, d, s) => {{
    set_text: text => set_text_state(d, s, text),
  }},
  init: (_, _, d, s, _, _) => {
    comp((_, _) => h("div", [Id(editor_page)], [
      h("div", [Id(editor_toolbar)], [
        h("div", [Id(editor_title)], [Str("Text Editor")]),
        h("div", [Id(editor_status)], [DynP(() => {
          let mode = if s.focused.get() { "focus" } else { "blur" }
          Str("\{mode}  Ln \{s.cursor_row.get() + 1}, Col \{s.cursor_col.get() + 1}")
        })]),
      ]),
      h("div", [Id(editor_content),
        Prop("tabIndex", Static(Int(0))),
        Event(Focus, _ => s.focused.set(true), EventCfg::new()),
        Event(Blur, _ => s.focused.set(false), EventCfg::new()),
        Event(KeyDown, ev => editor_keydown(d, s, ev), EventCfg::new(prevent=true)),
        Event(PointerDown, ev => {
          s.focused.set(true)
          match ev.target {
            Some(node) => node.focus()
            None => ()
          }
          match ev.data {
            Pointer(v) => {
              pointer_set_cursor(d, s, v.x, v.y, false)
              drag(ev, move_ev => {
                match move_ev.data {
                  Pointer(m) => pointer_set_cursor(d, s, m.x, m.y, true)
                  _ => ()
                }
              }, () => ())
            }
            _ => ()
          }
        }, EventCfg::new(prevent=true)),
      ], [
        h_map_dyn(
          () => d.lines.get().mapi((i, _) => (i, i)),
          (row, _) => h("div", [Id(editor_line)], [
            h("div", [Id(editor_num)], [Str((row + 1).to_string())]),
            h("div", [Id(editor_text)], [DynP(() => line_text_child(d, s, row))]),
          ]),
          ui_id=Some("lines"),
        ),
        h("textarea", [Id(editor_input),
          Prop("value", Dynamic(() => String(""))),
          Event(Input, ev => {
            match ev.data {
              Input(v) => if v.value != "" { insert_text(d, s, v.value) }
              _ => ()
            }
          }, EventCfg::new()),
          Event(KeyDown, ev => editor_keydown(d, s, ev), EventCfg::new(prevent=true)),
          Event(Focus, _ => s.focused.set(true), EventCfg::new()),
          Event(Blur, _ => s.focused.set(false), EventCfg::new()),
        ], []),
      ]),
    ]))
  },
}

fn init {
  try { text_editor.register() } catch { e => abort(e.to_string()) }
}
