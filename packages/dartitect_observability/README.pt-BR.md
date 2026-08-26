# dartitect_observability

[English](README.md)

## Objetivo

Logging estruturado, reporting, tracing W3C, redaction, sampling, dispatch
limitado e ownership de runtime sem prender a fornecedor. Logging local é o
padrão seguro; destinos remotos são opt-in.

## Quando usar

Use para contratos estáveis de telemetria sem ownership de SDK de fornecedor.
Não é collector, backend, exporter ou secret store.

## Quando não usar

Não adicione destinos remotos sem política explícita de dados, consentimento e
ownership. Não use para inicializar SDKs de provider ou registrar credenciais e
payloads de domínio.

## Combinações recomendadas

Combine com pacotes core/runtime por contratos injetados de logger, reporter e
tracer. Adicione `dartitect_sentry` somente para Hub Sentry inicializado pelo
consumidor e mantenha outros providers atrás de adapters customizados. Consulte o
[guia de seleção do ecossistema](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.pt-BR.md)
e as [receitas de implementação](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.pt-BR.md).

## Instalação

Este candidato não está publicado no pub.dev. Declare
`dartitect_observability: 1.0.0-rc.1` e use o
[guia de consumo do candidato Git](../../docs/guides/git-candidate-consumption.pt-BR.md)
para gerar o fechamento completo de overrides.

## Exemplo mínimo

```dart
final runtime = ObservabilityRuntime();
runtime.logger.info('Aplicação iniciada.');
await runtime.disposeAsync();
```

## Tour da API pública

- `ObservabilityRuntime` possui destinos e coordena flush/disposal.
- `DartitectLogger`, `LogEvent`, `LogSink` e `CallbackLogSink` definem logs.
- `ErrorReporter`, `ErrorEvent` e implementações no-op/callback definem erros.
- `Tracer`, `Span`, `TraceContext` e `W3CTracePropagator` definem tracing.
- `Redactor`, `SamplingPolicy` e `ObservabilityDiagnostics` aplicam políticas.
- `ArchitectureObserverBridge` mapeia sinais sem acoplar o core.
- `ReactiveObserverLoggerAdapter` mapeia eventos reativos sem payload para uma
  mensagem fixa e atributos allowlisted. O runtime os sanitiza novamente antes
  de qualquer destino local ou Sentry.

## Ownership

Crie um runtime por composition root de app/sessão/isolate. Descarte produtores
antes de flush/dispose dos destinos owned. Objetos de fornecedor podem ser
borrowed e pertencer ao consumidor.

## Limitações

Nunca registre authorization, cookies, tokens, passwords, bodies, headers,
queries, DSNs, identidade ou paths identificadores. Falhas de destinos ficam
isoladas; error/fatal nunca são eliminados por sampling.

## Extensão

Implemente `LogSink`, `ErrorReporter` ou `Tracer` e sanitize antes do fornecedor.
Veja o guia de integrações customizadas.

## Testes

Execute `dart test`. Use fakes graváveis e verifique redaction, overflow,
isolamento, fim exato de span e ordem de flush/disposal.

## Links

Veja [observabilidade](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/observability.pt-BR.md),
[integrações customizadas](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/custom-integrations.pt-BR.md) e o [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
