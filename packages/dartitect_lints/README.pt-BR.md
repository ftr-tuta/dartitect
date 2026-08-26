# dartitect_lints

[English](README.md)

## Objetivo

Diagnósticos de limites native-first com a API oficial
`analysis_server_plugin` do Dart.

## Quando usar

Use para feedback no editor/analyzer. Use `dartitect scan` como fallback
determinístico em CI ou hosts sem plugin.

## Quando não usar

Não use como dependência de runtime nem suponha que todo editor hospeda plugins
do analyzer. Ele reporta limites de arquitetura; não prova lógica de negócio,
cleanup de ownership ou comportamento de provider.

## Combinações recomendadas

Combine com scan/doctor de `dartitect_cli` em CI e testes focados de contratos de
runtime/provider. Mantenha suppressions locais justificadas e estreitas. Consulte o
[guia de seleção do ecossistema](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.pt-BR.md)
e as [receitas de implementação](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.pt-BR.md).

## Instalação

Este candidato não está publicado no pub.dev. Declare
`dartitect_lints: 1.0.0-rc.1` em `dev_dependencies` e use o
[guia de consumo do candidato Git](../../docs/guides/git-candidate-consumption.pt-BR.md)
para fixá-lo na tag protegida.

```yaml
# analysis_options.yaml
plugins:
  dartitect_lints:
```

Contribuidores usam o path local:

```yaml
plugins:
  dartitect_lints:
    path: packages/dartitect_lints
```

## Exemplo mínimo

Depois de ativar, `dart analyze` e editores compatíveis reportam os diagnósticos.
Veja `example/README.md` para a configuração completa.

## Tour da API pública

`plugin` é o entrypoint descoberto. `DartitectPlugin` registra a regra. Código
da aplicação não deve importar nenhum dos dois.

## Ownership

O analyzer possui o lifecycle do plugin. Ele somente lê a análise e não edita.

## Limitações

Warnings: `DT1001` domínio/Flutter; `DT1002` domínio/data; `DT1003`
data/presentation; `DT1004` `BuildContext` em limites internos; `DT1005`
presentation/infrastructure; `DT1006` framework proibido; `DT1007` import
privado cross-package.

Suprima apenas com justificativa:

```dart
// dartitect-ignore: DT1004 -- callback legado revisado
```

## Extensão

Mantenha paridade com `dartitect scan`, código/remediation estáveis e fixtures
do analyzer/scanner.

## Testes

Execute `dart test` e analise `tool/analyzer_plugin_fixture`. Pins estão no
ledger de dependências.

## Links

Veja [rationale](https://github.com/ftr-tuta/dartitect/blob/main/DEPENDENCIES.adoc),
[fallback CLI](https://github.com/ftr-tuta/dartitect/blob/main/packages/dartitect_cli/README.pt-BR.md) e o [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
