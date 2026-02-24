/-
Copyright (c) 2020 Marc Huisinga. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Authors: Marc Huisinga
-/
module

prelude
public import Lean.Data.Lsp

public section

namespace Lean.Lsp

inductive FileIdent where
  | uri (uri : DocumentUri)
  | mod (mod : Name)
  deriving Inhabited

instance : ToString FileIdent where
  toString
    | .uri uri => toString uri
    | .mod mod => toString mod

class FileSource (α : Type) where
  fileSource? : α → Option FileIdent
export FileSource (fileSource?)

instance : FileSource Location :=
  ⟨fun l => some (.uri l.uri)⟩

instance : FileSource TextDocumentIdentifier :=
  ⟨fun i => some (.uri i.uri)⟩

instance : FileSource VersionedTextDocumentIdentifier :=
  ⟨fun i => some (.uri i.uri)⟩

instance : FileSource TextDocumentEdit :=
  ⟨fun e => fileSource? e.textDocument⟩

instance : FileSource TextDocumentItem :=
  ⟨fun i => some (.uri i.uri)⟩

instance : FileSource TextDocumentPositionParams :=
  ⟨fun p => fileSource? p.textDocument⟩

instance : FileSource DidOpenTextDocumentParams :=
  ⟨fun p => fileSource? p.textDocument⟩

instance : FileSource DidChangeTextDocumentParams :=
  ⟨fun p => fileSource? p.textDocument⟩

instance : FileSource DidSaveTextDocumentParams :=
  ⟨fun p => fileSource? p.textDocument⟩

instance : FileSource DidCloseTextDocumentParams :=
  ⟨fun p => fileSource? p.textDocument⟩

instance : FileSource CompletionParams :=
  ⟨fun h => fileSource? h.toTextDocumentPositionParams⟩

instance : FileSource HoverParams :=
  ⟨fun h => fileSource? h.toTextDocumentPositionParams⟩

instance : FileSource DeclarationParams :=
  ⟨fun h => fileSource? h.toTextDocumentPositionParams⟩

instance : FileSource DefinitionParams :=
  ⟨fun h => fileSource? h.toTextDocumentPositionParams⟩

instance : FileSource TypeDefinitionParams :=
  ⟨fun h => fileSource? h.toTextDocumentPositionParams⟩

instance : FileSource ReferenceParams :=
  ⟨fun h => fileSource? h.toTextDocumentPositionParams⟩

instance : FileSource WaitForDiagnosticsParams :=
  ⟨fun p => some (.uri p.uri)⟩

instance : FileSource DocumentHighlightParams :=
  ⟨fun h => fileSource? h.toTextDocumentPositionParams⟩

instance : FileSource DocumentSymbolParams :=
  ⟨fun p => fileSource? p.textDocument⟩

instance : FileSource SemanticTokensParams :=
  ⟨fun p => fileSource? p.textDocument⟩

instance : FileSource SemanticTokensRangeParams :=
  ⟨fun p => fileSource? p.textDocument⟩

instance : FileSource FoldingRangeParams :=
  ⟨fun p => fileSource? p.textDocument⟩

instance : FileSource PlainGoalParams :=
  ⟨fun p => fileSource? p.textDocument⟩

instance : FileSource PlainTermGoalParams where
  fileSource? p := fileSource? p.textDocument

instance : FileSource RpcConnectParams where
  fileSource? p := some (.uri p.uri)

instance : FileSource RpcCallParams where
  fileSource? p := fileSource? p.textDocument

instance : FileSource RpcReleaseParams where
  fileSource? p := some (.uri p.uri)

instance : FileSource RpcKeepAliveParams where
  fileSource? p := some (.uri p.uri)

instance : FileSource CodeActionParams where
  fileSource? p := fileSource? p.textDocument

instance : FileSource InlayHintParams where
  fileSource? p := fileSource? p.textDocument

instance : FileSource SignatureHelpParams where
  fileSource? p := fileSource? p.textDocument

instance : FileSource DocumentColorParams where
  fileSource? p := fileSource? p.textDocument

instance : FileSource DocumentFormattingParams where
  fileSource? p := fileSource? p.textDocument

instance : FileSource DocumentRangeFormattingParams where
  fileSource? p := fileSource? p.textDocument

/--
Yields the file source of `item` by attempting to obtain `mod : Name` from `item.data?`.
Returns `none` if `item.data?` is not present or does not contain a parseable `mod` field.
Used when `completionItem/resolve` requests pass the watchdog to decide which file worker to forward
the request to.
All completion items returned by the server in `textDocument/completion`
requests should have a `data?` field that has a `mod` field.
-/
def CompletionItem.getFileSource? (item : CompletionItem) : Option FileIdent := do
  let data ← item.data?
  match data with
  | .obj _ =>
    -- In the language server, `data` is always an array,
    -- but we also support having `mod` as an object field for
    -- `chainLspRequestHandler` consumers.
    let mod ← (data.getObjValAs? Name "mod").toOption
    return .mod mod
  | .arr _ =>
    let val ← (data.getArrVal? 0).toOption
    let mod ← (fromJson? val).toOption
    return .mod mod
  | _ => none

instance : FileSource CompletionItem where
  fileSource? := CompletionItem.getFileSource?

end Lean.Lsp
