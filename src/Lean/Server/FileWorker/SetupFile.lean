/-
Copyright (c) 2023 Lean FRO, LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Sebastian Ullrich, Marc Huisinga
-/
module

prelude
public import Lean.Server.Utils
public import Lean.Util.LakePath
public import Lean.Server.ServerTask

public section

namespace Lean.Server.FileWorker

open IO

structure LakeSetupFileOutput where
    spawnArgs : Process.SpawnArgs
    exitCode  : UInt32
    stdout    : String
    stderr    : String

partial def runLakeSetupFile
    (m                 : DocumentMeta)
    (lakePath filePath : System.FilePath)
    (header            : ModuleHeader)
    (handleStderr      : String → IO Unit)
    : IO LakeSetupFileOutput := do
  let mut args := #["setup-file", filePath.toString, "-"]
  if m.dependencyBuildMode matches .never then
    args := args.push "--no-build" |>.push "--no-cache"
  let spawnArgs : Process.SpawnArgs := {
    stdin  := Process.Stdio.piped
    stdout := Process.Stdio.piped
    stderr := Process.Stdio.piped
    cmd    := lakePath.toString
    args
  }
  let lakeProc ← Process.spawn spawnArgs
  let (stdin, lakeProc) ← lakeProc.takeStdin
  stdin.putStrLn (toJson header).compress

  let rec drainStderr (acc : String) : IO String := do
    let line ← lakeProc.stderr.getLine
    if line == "" then
      return acc
    else
      handleStderr line
      drainStderr (acc ++ line)
  let stderr ← ServerTask.IO.asTask (drainStderr "")

  let stdout := String.trimAscii (← lakeProc.stdout.readToEnd) |>.copy
  let stderr ← IO.ofExcept stderr.get
  let exitCode ← lakeProc.wait
  return ⟨spawnArgs, exitCode, stdout, stderr⟩

/-- Categorizes possible outcomes of running `lake setup-file`. -/
inductive FileSetupResultKind where
  /-- File configuration loaded and dependencies updated successfully. -/
  | success
  /-- No Lake project found, no setup was done. -/
  | noLakefile
  /-- Imports must be rebuilt but `--no-build` was specified. -/
  | importsOutOfDate
  /-- Other error during Lake invocation. -/
  | error (msg : String)

/-- Result of running `lake setup-file`. -/
structure FileSetupResult where
  /-- Kind of outcome. -/
  kind        : FileSetupResultKind
  /-- Configuration from a successful setup, or else the default. -/
  setup       : ModuleSetup

def FileSetupResult.ofSuccess (setup : ModuleSetup) : IO FileSetupResult := do return {
  kind          := FileSetupResultKind.success
  setup
}

def FileSetupResult.ofNoLakefile (m : DocumentMeta) (header : ModuleHeader) : IO FileSetupResult := do return {
  kind          := FileSetupResultKind.noLakefile
  setup         := {name := m.mod, isModule := header.isModule}
}

def FileSetupResult.ofImportsOutOfDate (m : DocumentMeta) (header : ModuleHeader) : IO FileSetupResult := do return {
  kind          := FileSetupResultKind.importsOutOfDate
  setup         := {name := m.mod, isModule := header.isModule}
}

def FileSetupResult.ofError (m : DocumentMeta) (header : ModuleHeader) (msg : String) : IO FileSetupResult := do return {
  kind          := FileSetupResultKind.error msg
  setup         := {name := m.mod, isModule := header.isModule}
}

/-- Uses `lake setup-file` to compile dependencies on the fly and add them to `LEAN_PATH`.
Compilation progress is reported to `handleStderr`. Returns the search path for
source files and the options for the file. -/
partial def setupFile (m : DocumentMeta) (header : ModuleHeader) (handleStderr : String → IO Unit) : IO FileSetupResult := do
  let some filePath := System.Uri.fileUriToPath? m.uri
    | return ← FileSetupResult.ofNoLakefile m header -- untitled files have no lakefile

  let lakePath ← determineLakePath
  if !(← System.FilePath.pathExists lakePath) then
    return ← FileSetupResult.ofNoLakefile m header

  let result ← runLakeSetupFile m lakePath filePath header handleStderr

  match result.exitCode with
  | 0 =>
    let Except.ok (setup : ModuleSetup) := Json.parse result.stdout >>= fromJson?
      | return ← FileSetupResult.ofError m header s!"Invalid lake setup-file output:\n{result.stdout}"
    setup.dynlibs.forM loadDynlib
    FileSetupResult.ofSuccess setup
  | 2 => -- exit code for lake reporting that there is no lakefile
    FileSetupResult.ofNoLakefile m header
  | 3 => -- exit code for `--no-build`
    FileSetupResult.ofImportsOutOfDate m header
  | _ =>
    -- Prefer structured error from stdout (sent by Lake on build failure);
    -- fall back to stderr for errors that occur before the build starts.
    let stdout := result.stdout.trimAsciiEnd.toString
    let msg := if stdout.isEmpty then
      let stderr := result.stderr.trimAsciiEnd.toString
      if stderr.isEmpty then "lake setup-file failed" else stderr
    else stdout
    FileSetupResult.ofError m header msg
