# Servidor MCP local

[English](mcp.md)

## Escopo

`dartitect_mcp 1.0.0-rc.3` é local e somente STDIO. Usa
`dart_mcp 0.5.2`. Streamable HTTP, OAuth/autorização, plugins ChatGPT remotos,
UI MCP, shell/arquivos arbitrários, scaffolding `create` e acesso a apps em
execução estão fora do escopo.

## Configuração read-only

O candidato não está no pub.dev. Declare
`dartitect_mcp: 1.0.0-rc.3` em `dev_dependencies`, aplique o fechamento Git
completo do [guia de consumo do candidato](git-candidate-consumption.pt-BR.md)
e execute `dart run dartitect_mcp:dartitect_mcp --root .`.

Stdout fica reservado para JSON-RPC por linha. Diagnósticos usam stderr. O
processo aceita vários `--root`; todos devem existir.

## Codex

```console
codex mcp add dartitect -- dart run dartitect_mcp:dartitect_mcp --root .
codex mcp list
```

Ou salve `.codex/config.toml` no projeto trusted:

```toml
[mcp_servers.dartitect]
command = "dart"
args = ["run", "dartitect_mcp:dartitect_mcp", "--root", "."]
default_tools_approval_mode = "writes"
startup_timeout_sec = 20
tool_timeout_sec = 120
```

`writes` pede aprovação para tool não read-only. Inspeção/preview são read-only;
`dartitect_apply_change` é mutável/destrutiva. Instructions descrevem workflow
e restrições para o cliente.

## Clientes genéricos

Configure cliente local com STDIO e protocolo 2025-06-18+:

- comando: `dart`;
- argumentos: `run`, `dartitect_mcp:dartitect_mcp`, `--root`, `.`;
- environment: nenhum token, DSN, password ou credencial;
- aprovação: exija usuário para `dartitect_apply_change`.

Cada resultado retorna `structuredContent` e bloco textual JSON compatível.

## Tools read-only e resources

Inspect, scan, verify, doctor, explicação, conformidade e previews são
read-only. Scan e verify aceitam paginação limitada; verify combina arquitetura,
freshness de modelagem, overlap do ecossistema e status de providers. Doctor
deep é opt-in e tem timeout.

`dartitect_audit_conformance` declara projetos existentes como `audit_only`, usa
o scan sem baseline como evidência e nunca retorna passos de migração ou
coexistência.

Resources gerados:

- `dartitect://packages` e `dartitect://packages/{name}`;
- `dartitect://diagnostics/{code}`;
- `dartitect://guides/{slug}`;
- `dartitect://config/v1`.

Não há resource de arquivo livre.
O catálogo de guias inclui a matriz de seleção do ecossistema e as receitas de
implementação. Use a skill gerenciada `$dartitect-mcp` para configuração e
protocolo MCP; use `$dartitect-tooling` e a CLI diretamente em scripts ou CI.

## Escritas opt-in

Adicione `--allow-writes` somente para escrita local revisada. O flag não basta.

Model sync e migração para primary constructor usam o mesmo gate preview/apply
de init, baseline e sincronização de skills. O preview contém operações e
manifest semântico, nunca bodies de source do consumidor.

Apply exige simultaneamente:

1. opt-in do servidor;
2. preview read-only anterior;
3. plan ID opaco, não expirado e não usado;
4. `confirmed: true` após revisão;
5. aprovação do cliente MCP;
6. revalidação completa;
7. serialização e lock exclusivo.

Planos expiram em dez minutos e são single-use mesmo após tentativa falha.
Falhas estruturadas não expõem paths absolutos.

## Segurança de roots e dados

Paths de tools são relativos. Paths absolutos, traversal, segmentos vazios,
roots não autorizados, projetos ausentes e symlinks escapando o root canônico
são rejeitados. A própria raiz do filesystem não pode ser autorizada. O
servidor nunca retorna paths absolutos, credenciais, bodies,
headers, DSNs, environment ou erros internos não sanitizados.

## Troubleshooting

- `writes_disabled`: reinicie com `--allow-writes` somente se necessário.
- `plan_expired`, `plan_replayed` ou `stale_plan`: gere/revise novo preview.
- `change_locked`: aguarde a outra mudança local e crie novo preview.
- erros de root/path: use nome configurado e path relativo.
- timeout de startup: execute diretamente e veja stderr; não adicione segredos.

## Referências

As capacidades de transporte e protocolo seguem
[`dart_mcp 0.5.2`](https://pub.dev/packages/dart_mcp/versions/0.5.2). Registro,
campos TOML, instructions e aprovação no Codex seguem a
[documentação MCP oficial da OpenAI](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
