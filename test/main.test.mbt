// This file intentionally exists to test whether MoonBit recognizes `.test.mbt`
// inside `test/` as a test entry, and to demonstrate the test syntax.

test "test/main.test.mbt can import src package" {
  assert_eq(@lib.add_one(2), 3)
}
