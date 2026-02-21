import Lean

/-!
# Formatter: `return` must not break between keyword and argument

`doReturn` and `termReturn` use `checkLineEq`, so the argument must start
on the same line as `return`. Using `ppHardSpace` instead of `ppSpace`
prevents the formatter from inserting a line break there.
-/

open Lean PrettyPrinter

set_option hygiene false

-- Short struct: fits on one line
/--
info: def f : IO Unit := do
  return { x := 1 }
-/
#guard_msgs in #eval do ppCommand (← `(command| def f : IO Unit := do return { x := 1 }))

-- Wide struct: the primary bug case — must not break after `return`
/--
info: def f : IO Unit := do
  return { field1 := someLongValue, field2 := anotherLongValue, field3 := yetAnotherLongValue, field4 := moreStuff }
-/
#guard_msgs in #eval do ppCommand (← `(command| def f : IO Unit := do return { field1 := someLongValue, field2 := anotherLongValue, field3 := yetAnotherLongValue, field4 := moreStuff }))

-- Bare return (no argument)
/--
info: def f : IO Unit := do
  return
-/
#guard_msgs in #eval do ppCommand (← `(command| def f : IO Unit := do return))
