# dartitect_cli

[English](README.md)

## Objetivo

Inspeção local, scan, diagnósticos, migração de config, baseline revisado,
skills Codex e geradores transacionais no Dart VM, sem dependência de runtime.

## Quando usar

Use em desenvolvimento e CI. Comandos read-only servem para descoberta; revise
todo preview antes da escrita. Não executa shell arbitrário e não é build system.

## Quando não usar

Não embuta como comportamento de runtime da aplicação nem use como serviço
remoto. Use o pacote MCP somente quando um agente local precisar de tools/
resources tipados e limitados; scripts e CI devem chamar esta CLI diretamente.

## Combinações recomendadas

Combine com `dartitect_lints` para feedback no editor e com as onze skills Codex
gerenciadas para orientação focada. Use `dartitect_mcp` separadamente para
contexto local de agente. Consulte o
[guia de seleção do ecossistema](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.pt-BR.md)
e as [receitas de implementação](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.pt-BR.md).

## Instalação

```console
dart pub global activate dartitect_cli 1.0.0-rc.1
```

## Exemplo mínimo

```console
dartitect inspect --json
dartitect scan --no-baseline
dartitect doctor
dartitect model check
dartitect dependencies audit
```

Veja `example/README.md` para comandos e exit codes.

## Tour da API pública

- `DartitectProjectService` compartilha inspect/scan/doctor/mudanças tipadas.
- `ProjectScanner`, `DartitectFinding` e `CommandEnvelope` fornecem resultados.
- Config/migrator preservam chaves desconhecidas e originais.
- Baseline ignora linhas e usa código/path/evidence.
- `GenerationEngine` preserva generated-once e converge outputs de modelo com
  manifest via transações recuperáveis de create/update/delete.
- Gerador de modelos e auditor de dependências fornecem values nativos e
  política offline direta/transitiva.
- Sync distribui onze templates e substitui apenas skills com manifest; skills
  do consumidor permanecem intactas.
- Runner converte o serviço em exit codes estáveis.

## Ownership

Arquivos generated-once passam ao consumidor. Outputs de modelo e skills
fully-generated continuam do tooling apenas enquanto o digest forte do manifest
confere. `AGENTS.md` é preservado. `model sync` faz preview por padrão; somente
`--apply` escreve ou recupera.

## Limitações

Doctor deep roda analyzer somente sob opt-in. `create app` chama Flutter local.
Scan conservador não prova lógica de negócio.

## Extensão

Adicione operações tipadas ao serviço antes do rendering CLI. Não subprocessar
Dartitect nem analisar output humano em CLI/MCP.

## Testes

Execute `dart test`. Cubra Unicode/espaços, symlinks, traversal, conflitos,
I/O parcial, recovery, rollback, JSON e consumidores gerados.

## Links

Veja [início](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/getting-started.pt-BR.md),
[MCP](https://github.com/ftr-tuta/dartitect/blob/main/packages/dartitect_mcp/README.pt-BR.md) e o [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
