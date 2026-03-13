// This file intentionally exists to test whether MoonBit recognizes `.test.mbt`
// inside `src/test/` as a test entry, and to demonstrate the test syntax.

test "src/test main.test.mbt can call package code" {
  assert_eq(add_one(1), 2)
}
