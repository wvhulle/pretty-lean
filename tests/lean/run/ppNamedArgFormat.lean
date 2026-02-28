/-!
# Pretty printer: allOrNone grouping for named arguments in function applications

When a function application contains named arguments, the formatter uses
allOrNone grouping (either all args on one line, or each on its own line)
rather than greedy line-filling. This gives a record-like appearance.

Applications with only positional arguments retain the default fill behavior.
-/

-- Short positional application stays on one line
/--
info: Nat.add 1 2 : Nat
-/
#guard_msgs in
#check Nat.add 1 2

-- Positional application that fits stays flat
set_option pp.fieldNotation false in
/--
info: Nat.add (Nat.add 1 2) 3 : Nat
-/
#guard_msgs in
#check Nat.add (Nat.add 1 2) 3

-- Short named-arg application stays on one line
set_option pp.motives.all true in
set_option pp.fieldNotation false in
/--
info: fun n => Nat.rec (motive := fun x => Nat) 0 (fun k ih => ih + k) n : Nat → Nat
-/
#guard_msgs in
#check fun (n : Nat) => Nat.rec (motive := fun _ => Nat) 0 (fun k ih => ih + k) n

-- Long named-arg application: allOrNone grouping means all args get their own line
-- since the total doesn't fit in 120 columns
set_option pp.motives.all true in
set_option pp.fieldNotation false in
/--
info: fun n =>
  Nat.rec
    (motive :=
    fun x =>
    Nat × Nat × Nat × Nat × Nat)
    (0, 0, 0, 0, 0)
    (fun k ih =>
      (Prod.fst ih + k, Prod.fst (Prod.snd ih), Prod.fst (Prod.snd (Prod.snd ih)),
        Prod.fst (Prod.snd (Prod.snd (Prod.snd ih))), Prod.snd (Prod.snd (Prod.snd (Prod.snd ih))) + 1))
    n : Nat → Nat × Nat × Nat × Nat × Nat
-/
#guard_msgs in
#check fun (n : Nat) => Nat.rec (motive := fun _ => Nat × Nat × Nat × Nat × Nat) (0, 0, 0, 0, 0) (fun k ih => (ih.1 + k, ih.2.1, ih.2.2.1, ih.2.2.2.1, ih.2.2.2.2 + 1)) n
