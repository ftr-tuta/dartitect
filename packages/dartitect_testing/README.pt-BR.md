# dartitect_testing

[English](README.md)

## Objetivo

Probes provider-neutral, tempo manual, lifecycle, streams, telemetria gravável e
repository contract harnesses. Não exporta tipos de `package:test`.

## Quando usar

Use em testes consumidores que precisam de comportamento determinístico nos
limites Dartitect. Não prescreve runner ou framework de mocks.

## Quando não usar

Não substitua fixture provider/gerado real quando compatibilidade do SDK,
codegen, transações ou lifecycle nativo forem o comportamento testado. O pacote
não define contratos de produção.

## Combinações recomendadas

Combine com o limite runtime, reactive, offline-first, observability, adapter ou
tooling verificado pelo teste. Use fakes determinísticos para policy e fixture
real para integração. Consulte o
[guia de seleção do ecossistema](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.pt-BR.md)
e as [receitas de implementação](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.pt-BR.md).

## Instalação

Este candidato não está publicado no pub.dev. Declare
`dartitect_testing: 1.0.0-rc.3` em `dev_dependencies` e use o
[guia de consumo do candidato Git](../../docs/guides/git-candidate-consumption.pt-BR.md)
para gerar o fechamento completo de overrides.

## Exemplo mínimo

```dart
final order = <String>[];
final probe = DisposalProbe(label: 'database', order: order);
await probe.disposeAsync();
assert(order.single == 'database:disposeAsync');
```

## Tour da API pública

- `DisposalProbe` e `LifecycleHarness` expõem ordem/falhas de cleanup.
- `ManualClock` e `DeterministicTraceIdGenerator` removem aleatoriedade.
- sinks/reporters/tracers/spans graváveis tornam telemetria observável.
- `RepositoryContractHarness` executa casos reutilizáveis.
- helpers de stream limitam testes assíncronos.
- `DiagnosticsTopologyHarness` reconstrói topology, generation, revision e
  lifecycle terminal do protocolo v1 usando somente eventos opacos sem payload.

## Ownership

Cada teste cria e descarta seus fakes. Compartilhe logs/clocks apenas no escopo
do teste; não crie estado global.

## Limitações

Limites reais ainda exigem fixtures reais/aprovadas: modelo ObjectBox gerado,
adapter Dio mock e Hub Sentry fake sem rede.

## Extensão

Adicione fakes do consumidor ao lado do contrato. Mantenha o pacote livre de
APIs de test runner.

## Testes

Execute `dart test`; cubra falhas, cancelamento, retry, ordem, overflow,
isolamento e zero recursos residuais.

## Links

Veja a [matriz de testes](https://github.com/ftr-tuta/dartitect/blob/main/.agents/skills/dartitect-testing/references/test-matrix.md),
[integrações customizadas](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/custom-integrations.pt-BR.md) e o [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
