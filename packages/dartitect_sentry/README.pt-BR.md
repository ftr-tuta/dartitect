# dartitect_sentry

[English](README.md)

## Objetivo

Adapters de logs, erros e spans Dartitect para um `Hub` Sentry injetado. O
consumidor inicializa, configura e fecha Sentry.

## Quando usar

Use apenas após a aplicação selecionar e inicializar Sentry. Não é wrapper de
inicialização e nunca fornece DSN.

## Quando não usar

Não use antes da inicialização/consentimento do consumidor, como fonte de
contratos provider-neutral ou junto com captura Flutter, Dio ou tracing duplicada.

## Combinações recomendadas

Combine com `dartitect_observability`; injete Hub borrowed e descarte todos os
sinks/reporters/tracers Dartitect antes de o consumidor fechá-lo. Consulte o
[guia de seleção do ecossistema](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.pt-BR.md)
e as [receitas de implementação](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.pt-BR.md).

## Instalação

Este candidato não está publicado no pub.dev. Declare
`dartitect_sentry: 1.0.0-rc.2` e use o
[guia de consumo do candidato Git](../../docs/guides/git-candidate-consumption.pt-BR.md)
para gerar o fechamento completo de overrides.

## Exemplo mínimo

```dart
// O consumidor inicializa Sentry e possui este Hub.
final sink = SentryLogSink(hub: hub);
final runtime = ObservabilityRuntime(sinks: [LogSinkRegistration.borrowed(sink)]);
await runtime.disposeAsync(); // Não fecha hub.
```

O exemplo do pacote não usa rede nem DSN real.

## Tour da API pública

- `SentryLogSink` mapeia logs sanitizados para breadcrumbs/events.
- `SentryErrorReporter` mapeia erros inesperados com mechanism explícito.
- `SentryTracer` mapeia spans preservando contratos neutros.

Eventos reativos chegam ao Sentry somente por `ReactiveObserverLoggerAdapter`,
um `ObservabilityRuntime` e `SentryLogSink`. Assim o evento permanece sem
payload e recebe redaction no mapping do observer e no limite do destino.

## Ownership

Todos os adapters tomam o Hub borrowed. O consumidor o fecha depois que
produtores e recursos de observabilidade pararem e fizerem flush.

## Limitações

Não duplique captura com handlers globais ou `sentry_dio`. Bodies, headers,
queries, credenciais, DSNs e identidade não são atributos aceitos.

## Extensão

Mantenha mapping Sentry neste pacote isolado. Outros fornecedores devem
implementar contratos neutros.

## Testes

Execute `dart test`. Os testes usam Hub fake, zero rede, mapping sanitizado,
fim exato de span e lifetime borrowed.

## Links

Veja [observabilidade](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/observability.pt-BR.md),
[adapters](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/adapters.pt-BR.md) e o [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
