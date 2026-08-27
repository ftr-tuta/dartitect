# dartitect_mcp

[English](README.md)

## Objetivo

Acesso MCP local a inspeção, diagnósticos, conformidade, previews revisados e
documentação pública gerada na linha lockstep `1.0.0-rc.3`.

## Quando usar

Use com Codex ou outro cliente MCP local para contexto tipado/limitado. Use CLI
diretamente em scripts. Não é serviço remoto, plugin web, debugger ou shell.

## Quando não usar

Não use para automação shell/CI, acesso a arquivos arbitrários, HTTP/OAuth,
acesso remoto à aplicação ou escritas não supervisionadas. Não habilite writes
sem intenção de mutation local revisada.

## Combinações recomendadas

Combine com `dartitect_cli` como serviço de projeto compartilhado, mantendo
scripts na CLI. Use a skill gerenciada `$dartitect-mcp` para MCP e
`$dartitect-tooling` para shell/CI. Consulte o
[guia de seleção do ecossistema](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.pt-BR.md)
e as [receitas de implementação](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.pt-BR.md).

## Instalação

Este candidato não está publicado no pub.dev. Declare
`dartitect_mcp: 1.0.0-rc.3` em `dev_dependencies`, aplique os overrides do
[guia de consumo do candidato Git](../../docs/guides/git-candidate-consumption.pt-BR.md)
e execute `dart run dartitect_mcp:dartitect_mcp --root .`.

## Exemplo mínimo

```dart
final server = DartitectMcpServer(
  stdioChannel(input: stdin, output: stdout),
  policy: DartitectMcpPolicy(allowedRoots: [Directory.current]),
);
await server.done;
```

## Tour da API pública

- `DartitectMcpServer` implementa tools/resources num channel injetado.
- `DartitectMcpPolicy` canonicaliza roots, desliga escrita por padrão, limita
  resultados/tempo e injeta relógio/IDs.
- `DartitectMcpException` representa falhas sanitizadas.

Há nove tools fechadas: inspect, scan, doctor, explain, conformance, três previews
e apply. Não há `create`, leitura arbitrária, argumentos de processo ou shell.
Resources de pacotes/diagnósticos/guias/config são gerados e verificados; os
guias incluem seleção do ecossistema e receitas de implementação.

## Ownership

O host possui stdin/stdout e lifetime. A policy mantém apenas autorização de
roots. Fornecedores, credenciais e apps em execução ficam fora do MCP.

## Limitações

`dart_mcp` está fixado em `0.5.2`. Este release suporta somente STDIO local; sem
Streamable HTTP, OAuth/autorização, UI, plugin remoto ou acesso a apps. Stdout é
somente JSON-RPC; diagnósticos usam stderr.

## Extensão

Adicione operação tipada ao `DartitectProjectService` antes do mapping MCP. Não
subprocesse a CLI nem analise texto. Preserve paths relativos, sanitização,
schemas fechados, annotations e instructions.

## Testes

Execute `dart test`. A suíte usa cliente `dart_mcp` real in-process e STDIO,
sem modelo, rede, token ou conta.

## Configuração Codex

```console
codex mcp add dartitect -- dart run dartitect_mcp:dartitect_mcp --root .
```

```toml
[mcp_servers.dartitect]
command = "dart"
args = ["run", "dartitect_mcp:dartitect_mcp", "--root", "."]
default_tools_approval_mode = "writes"
startup_timeout_sec = 20
tool_timeout_sec = 120
```

Para escrita, adicione `--allow-writes`. Ainda são exigidos preview revisado,
plano single-use não expirado, `confirmed: true`, aprovação do cliente,
revalidação, serialização e lock. Read-only é recomendado.

## Clientes MCP genéricos

Configure cliente STDIO compatível com MCP 2025-06-18+ usando `dart` e os
argumentos `run dartitect_mcp:dartitect_mcp --root .`. Não inclua segredos e
exija aprovação de `dartitect_apply_change`.

## Links

Veja o [guia MCP](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/mcp.pt-BR.md), a
[política de segurança](https://github.com/ftr-tuta/dartitect/blob/main/SECURITY.pt-BR.md) e o [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
