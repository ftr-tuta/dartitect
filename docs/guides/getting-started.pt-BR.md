# Primeiros passos

[English](getting-started.md)

## Escolha o limite

Comece com `dartitect` para `Result` e ownership. Adicione
`dartitect_sync` somente para orquestração de datasets, `dartitect_flutter`
somente na composição de UI, observabilidade quando houver telemetria e adapters
apenas em infraestrutura. Testing, CLI, lints e MCP são escolhas de
desenvolvimento.

Use a [matriz de seleção do ecossistema](ecosystem-selection.pt-BR.md) para
verificar pacotes, entrypoints, plataformas, skills e contraindicações antes de
adicionar qualquer item.

## Instalação

O candidato não está publicado no pub.dev. Mantenha visíveis as versões dos
pacotes escolhidos e gere overrides Git para o fechamento interno completo:

```console
dart run tool/git_dependency_overrides.dart \
  dartitect,dartitect_sync,dartitect_flutter,dartitect_observability
```

Cole o resultado em `dependency_overrides`, execute `flutter pub get` e siga o
[guia de consumo do candidato Git](git-candidate-consumption.pt-BR.md) para
verificar URL, tag, paths dos pacotes e commit resolvido.

## Composição

Crie dependências no composition root de app/sessão/isolate com injeção por
construtor. Registre owned/borrowed. Descarte bindings/comandos,
watchers/queries, clients/Stores e observabilidade. Fornecedores owned pelo
consumidor fecham depois.

## Validação

```console
dart run dartitect_cli:dartitect inspect --json
dart run dartitect_cli:dartitect scan --no-baseline
dart run dartitect_cli:dartitect doctor
dart test
```

Resolva violações novas. Crie baseline apenas para dívida existente revisada e
remova entradas obsoletas com o tempo.

## Orientação para agentes

`dartitect codex sync --dry-run` mostra preview de dez skills gerenciadas com
invocação implícita. Greenfield e brownfield começam com `$dartitect-design` e
`$dartitect-adopt`; implementação focada segue para runtime, reactive,
offline-first, observability, adapters, testing, tooling ou MCP. O sync nunca
gerencia a skill local `repository-contribution` deste repositório.

## Próximo passo

Use as [receitas de implementação](implementation-recipes.pt-BR.md) e então leia
os guias de composição, commands, reactive, observabilidade, adapters,
integrações customizadas ou MCP para o limite alterado.
