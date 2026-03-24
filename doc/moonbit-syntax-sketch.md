# MoonBit 语法粗描

这份文档不是官方语法，也不追求完整 grammar。这里只是基于 `../parser-master` 当前暴露出来的结构，整理了一份“MoonBit parser 实际上在处理什么”的粗描，方便后面继续讨论 MoonBit 版的组合子 parser。

这里主要想把 parser 眼里的几层东西分清楚，不去追求把语言规则列完。

## 1. 从 parser 仓库看，MoonBit 语法不止是一份 grammar

`parser-master` 现在的结构很清楚：

- `top.mbt`
- `tokens/`
- `lexer/`
- `syntax/`
- `handrolled_parser/`
- `yacc_parser/`

也就是说，MoonBit parser 当前比“一个 grammar 文件 + 一个生成器”复杂得多，至少分成了：

1. token 和位置、注释等底层表示
2. lexer
3. AST
4. 手写 parser
5. yacc parser
6. 顶层入口和 docstring 绑定

[top.mbt](/D:/Users/ch3co/Desktop/mbt_race/parser-master/top.mbt#L108) 的 `parse_string`
也说明了这一点：它先调 lexer，然后在 `MoonYacc` 和 `Handrolled` 两条 parser 路之间选一条，最后再把
docstring 重新挂回语法树。

所以如果只是问“MoonBit 语法大概长什么样”，更值得看的是这几层东西：

- token 长什么样
- AST 长什么样
- parser 入口按什么层次在吃这些东西

## 2. 顶层入口看见的东西

从 [top.mbt](/D:/Users/ch3co/Desktop/mbt_race/parser-master/top.mbt#L108) 看，当前 parser 入口处理的是：

- `source : String`
- `tokens`
- `docstrings`
- `parser = Handrolled | MoonYacc`
- 输出 `(@syntax.Impls, Array[Report])`

这很重要，因为它说明 parser 的目标更接近下面这两样：

- 一组顶层实现项 `Impls`
- 一组诊断 `Report`

也就是说，MoonBit parser 当前的主要职责是：

1. 把源码转成 AST
2. 带上位置
3. 带上错误
4. 把 docstring 重新挂到对应节点上

这里可以直接看成一套完整的语法解析入口：它的目标是 AST、位置和诊断。后面如果要对齐 MoonBit 这边的语法，
目标产物也应该落在这一层，而不是只盯着规则本身。

## 3. token 层：parser 真正在消费什么

从 [yacc_parser/parser.mbty](/D:/Users/ch3co/Desktop/mbt_race/parser-master/yacc_parser/parser.mbty#L9)
能看到 parser 当前会消费的 token 大类：

- 标识符
  - `LIDENT`
  - `UIDENT`
  - `PACKAGE_NAME`
  - `DOT_LIDENT`
  - `DOT_UIDENT`
- 字面量
  - `INT`
  - `FLOAT`
  - `DOUBLE`
  - `STRING`
  - `CHAR`
  - `BYTE`
  - `BYTES`
  - `INTERP`
  - `MULTILINE_INTERP`
  - `REGEX_LITERAL`
- 注解和注释
  - `ATTRIBUTE`
  - `COMMENT`
  - `NEWLINE`
- 关键字
  - `FN`
  - `LET`
  - `CONST`
  - `MATCH`
  - `STRUCT`
  - `ENUM`
  - `TYPE`
  - `TRAIT`
  - `IMPL`
  - `IF`
  - `ELSE`
  - `TRY`
  - `CATCH`
  - `FOR`
  - `WHILE`
  - `TEST`
  - `USING`
  - `PUB`
  - `PRIV`
  - `EXTERN`
  - `ASYNC`
  - `RAISE`
  - `NORAISE`
- 操作符和标点
  - `COLON`
  - `COLONCOLON`
  - `THIN_ARROW`
  - `FAT_ARROW`
  - `DOTDOT`
  - `RANGE_*`
  - `PIPE`
  - `BAR`
  - `AMPER`
  - `AMPERAMPER`
  - `BARBAR`
  - `QUESTION`
  - `EXCLAMATION`
  - `LPAREN`
  - `LBRACE`
  - `LBRACKET`
  - `COMMA`
  - `SEMI`

这层最直接的启发是：MoonBit parser 当前消费的是带类型的 token 流，不是裸字符流。

但这里要特别记一条你前面已经明确说过的约束：

- 用户明确表示 lexer 是 parser-driven 的
- 这里不能简单理解成“先把整份源码完整 token 化，再把 token 交给 parser”
- lexer 单独存在，是为了错误恢复和上下文相关切分

所以这份 token 列表只说明“parser 最终会消费这些类别”，不代表 MoonBit 版一定要走传统先全量 lex 的路线。

## 4. syntax 层：MoonBit parser 眼里的 AST 轮廓

从 [syntax/ast.mbt](/D:/Users/ch3co/Desktop/mbt_race/parser-master/syntax/ast.mbt#L9) 看，
MoonBit 当前的 AST 至少明确分出了这些核心层次。

### 4.1 名字和可见性

- `Visibility`
- `LongIdent`
- `TypeName`
- `ConstrId`
- `Label`
- `Binder`
- `Var`

这说明 parser 不会把名字全都压成普通字符串，至少会区分：

- 普通标识符
- 带包前缀的名字
- 类型名 / 构造器名 / 变量名
- 字段 label

### 4.2 类型

当前能直接看到的 `Type` 形状有：

- `Any`
- `Arrow`
- `Tuple`
- `Name`
- `Option`
- `Object`

再配合 `ErrorType`、`TypeVarBinder`、`TypeVarConstraint`，说明 MoonBit 的类型层至少已经包含：

- 函数类型
- tuple 类型
- 类型应用
- option 写法
- async / raise / noraise 这类函数类型修饰
- 类型变量及其约束

### 4.3 类型声明

`TypeDesc` 当前分成：

- `Abstract`
- `Extern`
- `Error`
- `Variant`
- `Record`
- `TupleStruct`
- `Alias`

这基本就是 MoonBit 顶层类型声明的主干。

从 parser 的角度看，MoonBit 的 `type / struct / enum / suberror / extern type`
最后都会收进同一层类型声明树里，看起来不是几套完全平行的东西。

### 4.4 常量和字段

`Constant` 当前包括：

- `Bool`
- `Byte`
- `Bytes`
- `Char`
- `Int`
- `Int64`
- `UInt`
- `UInt64`
- `Float`
- `Double`
- `String`
- `BigInt`

字段定义则至少有：

- `FieldDecl`
- `ConstrParam`
- `ConstrDecl`

这意味着 parser 当前对字面量和字段信息保留得相当细，后面如果要兼容这一层，lexer 和 parser 都不能过于粗糙。

## 5. handrolled parser 暴露出来的语法面

手写 parser 比 yacc grammar 更能说明“MoonBit 实际上是怎么被吃进去的”。

从 [handrolled_parser/parser.mbt](/D:/Users/ch3co/Desktop/mbt_race/parser-master/handrolled_parser/parser.mbt#L42)
开始，可以看出几件事。

### 5.1 顶层是按实现项逐个读的

`parse_toplevel` 看起来更像是在循环里逐个吃顶层项：

- 同步到一个顶层开始集合
- `parse_top()`
- 看结尾是不是分号、换行或 EOF
- 出错时报告 `Missing newline here` 或 `Unexpected token here`

所以 MoonBit 顶层真正麻烦的地方主要在这里：

- 换行
- 分号
- 同步点
- 错误恢复

### 5.2 名字解析有明显的上下文分化

当前至少有这些入口：

- `parse_qual_lident`
- `parse_qual_luident`
- `parse_luident`
- `parse_binder`
- `parse_type_name`
- `parse_fun_binder`

这说明 MoonBit 里“名字”这件事不能粗暴统一成 `ident`。parser 当前明确在区分：

- 只该出现小写的地方
- 大小写都行的地方
- 可带包前缀的地方
- 方法定义里的 `TypeName::func`
- 带 `&` 前缀的 object type name

如果以后要用组合子表达 MoonBit，这类入口很可能要保留成单独的小 parser，别全塞进一个“标识符组合子”里。

### 5.3 attributes 是前缀批量解析的

`parse_attributes` 的形状很简单：一直吃 `ATTRIBUTE(content)`，直到下一个 token 不再是 attribute。

这点很适合组合子表达，因为它本质上就是：

- `repeat(attribute)`
- 然后挂到后面的声明上

### 5.4 错误恢复是 parser 主体的一部分

当前手写 parser 到处都带着：

- `panic`
- `report_unexpected`
- `push_sync`
- `push_syncs`
- `pop_syncs`

这说明错误恢复本来就在 parser 主体里，不是额外再补的一层。

这和你原本 JS 版把 lexer 和 parser 设计成服务恢复的思路是一致的：恢复这件事就是 parse 过程本身的一部分。

## 6. yacc grammar 暴露出来的语法骨架

虽然你现在不打算做 yacc，但 [yacc_parser/parser.mbty](/D:/Users/ch3co/Desktop/mbt_race/parser-master/yacc_parser/parser.mbty#L9)
还是很有参考价值，因为它把当前 MoonBit 语法里最基础、最常重复的结构直接摊开了。

当前最明显的几类骨架是：

### 6.1 列表和分隔符

里面有很多通用规则：

- `non_empty_list`
- `non_empty_list_commas`
- `list_commas`
- `non_empty_list_semis`
- `list_semis`
- `*_with_trailing_info`

这说明 MoonBit 语法有大量：

- 逗号分隔列表
- 分号分隔列表
- 可尾逗号
- 可尾分号
- 需要保留 trailing 信息的结构

如果后面用组合子表达，列表组合子会是非常核心的一层，不会只是附属小工具。

### 6.2 参数和注解

像 `parameter -> Parameter`、`annot -> Type`、`opt_annot -> Type?` 这些规则说明：

- 参数本身就是一层结构
- 类型注解是一层独立可选结构
- `_`、普通 binder、post label 这些是参数里的不同分支

### 6.3 优先级和表达式

`parser.mbty` 里有明确的 precedence 声明：

- `BARBAR`
- `AMPERAMPER`
- `BAR`
- `CARET`
- `AMPER`
- `INFIX1..4`
- `PLUS`
- `MINUS`
- `as`
- `!`
- `?`

这说明 MoonBit 表达式层不能按简单的无优先级 PEG 链式结构去理解。

用户明确表示：

- PEG 组合子不应该支持左递归
- 左递归语法应该用 Pratt 表达

所以如果以后用你那套 MoonBit 组合子去写表达式层，合理方向就是：

- 其他结构照常用 PEG 组合子
- 表达式和操作符优先级部分专门走 Pratt

## 7. 从 parser 仓库反推，MoonBit 语法可以先拆成哪几层

如果只为了后面在 MoonBit 里复刻你 JS 版那套 parser 体系，这门语言现在比较适合先被拆成四层。

### 7.1 lexer 驱动层

这层负责：

- 当前位置可读出的 token 片段
- 空白和换行
- 注释和 docstring
- 字面量和标识符类别
- 恢复时的重新同步

这里不能写成“独立先扫完整文件”的传统 lexer 心智。

### 7.2 顶层声明层

这层主要包括：

- `let`
- `const`
- `fn`
- `type`
- `struct`
- `enum`
- `trait`
- `impl`
- `using`
- `test`

这是最适合先跑通的一层，因为从 handrolled parser 看，MoonBit 顶层本身已经是“逐个声明解析”的结构。

### 7.3 类型 / pattern / 参数层

这层包括：

- type name
- type application
- arrow type
- field
- constructor param
- pattern
- binder
- labelled parameter

这部分递归比较多，但局部结构都很清楚。

### 7.4 表达式层

这层最复杂，至少要分两块：

- 普通表达式结构：block / if / match / call / field access / literal / record / array
- 操作符和优先级：走 Pratt

## 8. 和你那套 JS 组合子的兼容性判断

按 `parser-master` 当前暴露出来的结构看，MoonBit 语法本身没有超出你原来那套 JS parsergen 的表达边界。

能直接对上的部分有：

- 顺序结构：`chain`
- 选择分支：`oneof`
- 可选结构：`maybe`
- 列表结构：`repeat` 加逗号/分号 helper
- 前缀结构：attributes、visibility、binder、annotation
- 顶层递归结构：type / pattern / decl / expr 子树

真正不能省掉的是这些运行时和分析能力：

- Pratt
- memo / packrat
- 错误恢复
- parser-driven lexer
- 位置信息
- docstring / comment 的重新绑定

这里再按你的原话把两条关键约束写死：

- 用户明确表示 PEG 组合子不应该支持左递归，左递归语法应该用 Pratt 表达
- 用户明确表示 lexer 是 parser-driven 的，lexer 单独拆出来是为了更好地做错误恢复

所以当前结论可以直接写成：

- **能写**
- **而且主体结构没有超出你原来 JS 版的能力范围**
- **真正要保住的是 parser-driven lexer、恢复、Pratt 和 memo 这些语义**

## 9. 参考位置

这份文档主要对照了这些文件：

- [README.mbt.md](/D:/Users/ch3co/Desktop/mbt_race/parser-master/README.mbt.md)
- [top.mbt](/D:/Users/ch3co/Desktop/mbt_race/parser-master/top.mbt)
- [syntax/ast.mbt](/D:/Users/ch3co/Desktop/mbt_race/parser-master/syntax/ast.mbt)
- [handrolled_parser/parser.mbt](/D:/Users/ch3co/Desktop/mbt_race/parser-master/handrolled_parser/parser.mbt)
- [yacc_parser/parser.mbty](/D:/Users/ch3co/Desktop/mbt_race/parser-master/yacc_parser/parser.mbty)
