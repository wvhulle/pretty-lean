/-
Copyright (c) 2025 Lean FRO, LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

prelude
public import Lean.Server.Requests
import Lean.PrettyPrinter

public section

namespace Lean.Server.FileWorker.Formatting
open Lsp
open Snapshots

/-- Strip trailing lines that are pure comments or blank from ppCommand output.
The formatter's `pushToken` preserves trailing `SourceInfo` comments at incorrect
indentation (nested under the last expression). The gap extraction re-includes them
at their correct original indentation.
Scans backward from the end so only trailing lines are inspected. -/
private partial def trimTrailingCommentLines (s : String) : String :=
  -- Walk backward line by line. A line is "comment-only" if, after stripping
  -- leading whitespace, it is empty or starts with "--".
  go s.rawEndPos
where
  -- Find the start of the line ending just before `pos` (the char at `pos` is '\n' or end).
  findLineStart (pos : String.Pos.Raw) : String.Pos.Raw :=
    if pos == 0 then 0
    else
      let p := ⟨pos.byteIdx - 1⟩
      let c := String.Pos.Raw.get s p
      if c == '\n' then pos
      else findLineStart p
  isCommentOrBlankLine (lineStart lineEnd : String.Pos.Raw) : Bool :=
    let rec scan (i : String.Pos.Raw) : Bool :=
      if i >= lineEnd then true  -- blank line
      else
        let c := String.Pos.Raw.get s i
        if c == ' ' || c == '\t' then scan (String.Pos.Raw.next s i)
        else if c == '-' then
          let j := String.Pos.Raw.next s i
          j < lineEnd && String.Pos.Raw.get s j == '-'  -- "--" prefix
        else false
    scan lineStart
  go (pos : String.Pos.Raw) : String :=
    if pos == 0 then ""
    else
      -- pos points one past the last char we're considering (either '\n' or end)
      let lineStart := findLineStart pos
      if isCommentOrBlankLine lineStart pos then
        -- Skip this trailing line; also skip the preceding '\n' if present
        let cutpoint := if lineStart > 0 then ⟨lineStart.byteIdx - 1⟩ else 0
        go cutpoint
      else
        String.Pos.Raw.extract s 0 pos

/-- Collapse runs of 3+ consecutive newlines down to 2 (at most one blank line). -/
private partial def collapseBlankLines (s : String) : String :=
  go 0 0 ""
where
  go (i : String.Pos.Raw) (nlCount : Nat) (acc : String) : String :=
    if i < s.rawEndPos then
      let c := String.Pos.Raw.get s i
      if c == '\n' then
        let nlCount' := nlCount + 1
        let acc' := if nlCount' ≤ 2 then acc.push '\n' else acc
        go (String.Pos.Raw.next s i) nlCount' acc'
      else
        go (String.Pos.Raw.next s i) 0 (acc.push c)
    else acc

/-- Format commands in `[rangeStart, rangeEnd)` byte range. Commands outside the range
are emitted verbatim from the original source. Returns a full-document `TextEdit`. -/
def formatCommandRange
    (doc : EditableDocument) (text : FileMap)
    (initSnap : Language.Lean.InitialSnapshot)
    (headerParsed : Language.Lean.HeaderParsedState)
    (headerSuccess : Language.Lean.HeaderProcessedState)
    (rangeStart rangeEnd : String.Pos.Raw)
    : EIO RequestError (Array TextEdit) := do
  -- Collect all parsed command syntax by walking the CommandParsedSnapshot chain.
  let mut cmdStxs : Array Syntax := #[]
  let mut next? := some headerSuccess.firstCmdSnap
  repeat do
    match next? with
    | none => break
    | some snapshotTask =>
      let cmdParsed := snapshotTask.get
      cmdStxs := cmdStxs.push cmdParsed.stx
      next? := cmdParsed.nextCmdSnap?
  let headerSnap : Snapshots.Snapshot := {
    stx := initSnap.stx
    mpState := headerParsed.parserState
    cmdState := headerSuccess.cmdState
  }
  -- Emit header (imports) verbatim — ppCommand would incorrectly indent it.
  let headerStx := initSnap.stx
  let mut result : String := ""
  let headerOriginal := match headerStx.getPos?, headerStx.getTailPos? with
    | some s, some e => String.Pos.Raw.extract text.source s e
    | _, _ => headerStx.reprint.getD ""
  result := result ++ headerOriginal.trimAsciiEnd.copy
  let mut prevTailPos := headerStx.getTailPos?
  for stx in cmdStxs do
    match prevTailPos, stx.getPos? with
    | some prevEnd, some curStart =>
      let gap := String.Pos.Raw.extract text.source prevEnd curStart
      result := result ++ collapseBlankLines gap
    | none, _ => pure ()
    | _, none => result := result ++ "\n"
    let cmdStart := stx.getPos?.getD 0
    let cmdEnd := stx.getTailPos?.getD 0
    let overlaps := cmdStart < rangeEnd && cmdEnd > rangeStart
    if overlaps then
      let fmtResult ← (headerSnap.runCoreM doc.meta (PrettyPrinter.ppCommand ⟨stx⟩)).toBaseIO
      let formatted := match fmtResult with
        | .ok fmt => trimTrailingCommentLines fmt.pretty.trimAsciiEnd.copy
        | .error _ => trimTrailingCommentLines (stx.reprint.getD "").trimAsciiEnd.copy
      result := result ++ formatted
    else
      -- Outside requested range: emit original source verbatim
      let original := match stx.getPos?, stx.getTailPos? with
        | some s, some e => String.Pos.Raw.extract text.source s e
        | _, _ => stx.reprint.getD ""
      result := result ++ original.trimAsciiEnd.copy
    prevTailPos := stx.getTailPos?
  let endPos := text.utf8PosToLspPos text.source.rawEndPos
  let fullRange : Range := ⟨⟨0, 0⟩, endPos⟩
  return #[{ range := fullRange, newText := result }]

end Lean.Server.FileWorker.Formatting
