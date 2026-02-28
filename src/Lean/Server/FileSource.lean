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

class FileSource (α : Type) where
  fileSource? : α → Option DocumentUri
export FileSource (fileSource?)

instance : FileSource Location :=
  ⟨fun l => some l.uri⟩

instance : FileSource TextDocumentIdentifier :=
  ⟨fun i => some i.uri⟩

instance : FileSource VersionedTextDocumentIdentifier :=
  ⟨fun i => some i.uri⟩

instance : FileSource TextDocumentEdit :=
  ⟨fun e => fileSource? e.textDocument⟩

instance : FileSource TextDocumentItem :=
  ⟨fun i => some i.uri⟩

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
  ⟨fun p => some p.uri⟩

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
  fileSource? p := some p.uri

instance : FileSource RpcCallParams where
  fileSource? p := fileSource? p.textDocument

instance : FileSource RpcReleaseParams where
  fileSource? p := some p.uri

instance : FileSource RpcKeepAliveParams where
  fileSource? p := some p.uri

instance : FileSource CodeActionParams where
  fileSource? p := fileSource? p.textDocument

instance : FileSource InlayHintParams where
  fileSource? p := fileSource? p.textDocument

instance : FileSource SignatureHelpParams where
  fileSource? p := fileSource? p.textDocument

instance : FileSource DocumentColorParams where
  fileSource? p := fileSource? p.textDocument

/--
Yields the file source of `item` by attempting to obtain `uri : DocumentUri` from `item.data?`.
Returns `none` if `item.data?` is not present or does not contain a parseable `uri` field.
Used when `completionItem/resolve` requests pass the watchdog to decide which file worker to forward
the request to.
All completion items returned by the server in `textDocument/completion`
requests should have a `data?` field that has a `uri` field.
-/
def CompletionItem.getFileSource? (item : CompletionItem) : Option DocumentUri := do
  let data ← item.data?
  match data with
  | .obj _ =>
    -- In the language server, `data` is always an array,
    -- but we also support having `uri` as an object field for
    -- `chainLspRequestHandler` consumers.
    let uri ← (data.getObjValAs? DocumentUri "uri").toOption
    return uri
  | .arr _ =>
    let val ← (data.getArrVal? 0).toOption
    let uri ← (fromJson? val).toOption
    return uri
  | _ => none

instance : FileSource CompletionItem where
  fileSource? := CompletionItem.getFileSource?

end Lean.Lsp
