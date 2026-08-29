# Semantic API compatibility fixture

This package compiles representative application, extension-author,
generated-code, adapter-author, and tooling/test consumers against the public
entrypoints recorded by `tool/api_surface.snapshot.json`.

It contains no application business rules and is validated as a downstream
package by the workspace analyzer and test gates.
