# dartitect_cli

[English](README.md)

## Objetivo

Inspeção local, scan, diagnósticos, validação de config, baseline revisado,
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
dart pub global activate dartitect_cli 1.0.0-rc.3
```

## Exemplo mínimo

```console
dartitect inspect --json
dartitect scan --no-baseline
dartitect doctor
dartitect model check
dartitect model migrate primary
dartitect dependencies audit
dartitect fleet versions apps/a apps/b --root . --json
dartitect fleet check apps/a apps/b --root . --json
```

Veja `example/README.md` para comandos e exit codes.

## Tour da API pública

- `DartitectProjectService` compartilha inspect/scan/doctor/mudanças tipadas.
- `DartitectFleetService` limita roots explícitos e fornece relatórios offline
  de versões/check/policy fixada, além de previews de upgrade.
- `DartitectChangePlan` expõe manifest ordenado de inputs semânticos. O digest
  SHA-256 é revalidado sob lock de projeto do SO mantido até commit ou rollback;
  assets irrelevantes não invalidam o plano.
- `ProjectScanner`, `DartitectFinding` e `CommandEnvelope` fornecem resultados.
- Config/migrator preservam chaves desconhecidas e originais.
- Baseline ignora linhas e usa código/path/evidence.
- `GenerationEngine` preserva generated-once e converge outputs de modelo com
  manifest via transações recuperáveis de create/update/delete.
- Gerador de modelos e auditor de dependências fornecem values nativos e
  política offline direta/transitiva.
- A migração de primary constructors fornece preview/apply semântico com lock
  compartilhado, journal próprio de source e rollback integral.
- Sync distribui onze templates e substitui apenas skills com manifest; skills
  do consumidor permanecem intactas.
- Runner converte o serviço em exit codes estáveis.

## Ownership

Arquivos generated-once passam ao consumidor. Outputs de modelo e skills
fully-generated continuam do tooling apenas enquanto o digest forte do manifest
confere. `AGENTS.md` é preservado. `model sync` faz preview por padrão; somente
`--apply` escreve ou recupera.
Ignore `.dartitect/project-change.lock`; o path estável é necessário para que
processos concorrentes coordenem no mesmo inode de lock do SO.
A CLI de frota é read-only; `fleet upgrade` exige `--dry-run`. Bundles de policy
são locais e fixados pelos digests SHA-256 do bundle e da policy informados pelo
chamador. Veja o [guia de tooling de frota](../../docs/guides/fleet-tooling.pt-BR.md).

## Limitações

Doctor deep roda analyzer somente sob opt-in. `create app` chama Flutter local.
Scan conservador não prova lógica de negócio.

## Extensão

Adicione operações tipadas ao serviço antes do rendering CLI. Não subprocessar
Dartitect nem analisar output humano em CLI/MCP.

## Testes

Execute `dart test`. Cubra Unicode/espaços, symlinks, traversal, conflitos,
I/O parcial, recovery, rollback, JSON e consumidores gerados.
Os testes de corrida cross-process e lock interrompido rodam em Linux, Windows
e macOS pela matriz de verificação do repositório.

## Links

Veja [início](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/getting-started.pt-BR.md),
[MCP](https://github.com/ftr-tuta/dartitect/blob/main/packages/dartitect_mcp/README.pt-BR.md) e o [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
