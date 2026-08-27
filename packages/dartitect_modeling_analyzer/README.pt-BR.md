# dartitect_modeling_analyzer

[English](README.md)

## Finalidade

Compiler semântico read-only baseado em Analyzer, compartilhado pela CLI e
pelos lints oficiais. Ele resolve libraries uma vez, valida primary constructors
por identidade de elemento e `DartType` e expõe IR de workspace neutro ao
renderer, diagnostics estáveis e edições semânticas de source. Aplicativos em
runtime nunca devem depender deste package.
