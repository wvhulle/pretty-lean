import Lean.Data.Lsp

/-!

Usage: `lsp-probe FILE.lean`

A small CLI for driving `lean --server` via `Lean.Lsp.Ipc` and dumping every
published diagnostic for a target file. Useful for debugging language-server
behavior end-to-end without a real editor in the loop.

Mirrors the test pattern in `tests/server/diags.lean` — initialize, didOpen,
`Ipc.collectDiagnostics`, shutdown — but as an installed binary instead of a
CTest-only script.

The spawned server defaults to `lean` on `PATH`; override with
`LEAN_PROBE_BIN=/path/to/lean lsp-probe FILE.lean`.

-/

open IO Lean Lsp JsonRpc

def severityName : Option DiagnosticSeverity → String
  | some .error => "Error"
  | some .warning => "Warning"
  | some .information => "Info"
  | some .hint => "Hint"
  | none => "?"

def main (args : List String) : IO UInt32 := do
  let some path := args[0]? | do
    eprintln "usage: lsp-probe FILE.lean"
    return 1
  let abs ← IO.FS.realPath (System.FilePath.mk path)
  let uri := System.Uri.pathToUri abs.toString
  let text ← FS.readFile abs

  let leanBin := (← IO.getEnv "LEAN_PROBE_BIN").getD "lean"
  Ipc.runWith leanBin #["--server"] do
    Ipc.writeRequest ⟨0, "initialize",
      (toJson <| ({ processId? := none, capabilities := {}, rootUri? := some uri }
        : InitializeParams))⟩
    discard <| Ipc.readResponseAs 0 InitializeResult
    Ipc.writeNotification ⟨"initialized", InitializedParams.mk⟩

    Ipc.writeNotification ⟨"textDocument/didOpen",
      ({ textDocument := { uri, languageId := "lean", version := 1, text }
         : DidOpenTextDocumentParams })⟩

    let some notif ← Ipc.collectDiagnostics 1 uri 1
      | do
        println "no diagnostics received"
        Ipc.shutdown 99
        discard <| Ipc.waitForExit
    let diags := notif.param.diagnostics
    println s!"=== {diags.size} diagnostics ==="
    for d in diags do
      let line := d.range.start.line
      let col := d.range.start.character
      let code := match d.code? with
        | some (.string s) => s
        | some (.int n) => toString n
        | none => "-"
      let related := (d.relatedInformation?.getD #[]).size
      let tags := (d.tags?.getD #[]).size
      let msg := d.message.replace "\n" " ⏎ "
      let dataLen := d.data?.map (·.compress.length) |>.getD 0
      println s!"  L{line}:{col} {severityName d.severity?} [{code}] tags={tags} related={related} data={dataLen}b"
      println s!"    msg: {msg}"
      for ri in d.relatedInformation?.getD #[] do
        let rline := ri.location.range.start.line
        println s!"      ↳ L{rline}: {ri.message}"
      if let some json := d.data? then
        println s!"      data: {json.compress}"

    Ipc.shutdown 2
    discard <| Ipc.waitForExit

  return 0
