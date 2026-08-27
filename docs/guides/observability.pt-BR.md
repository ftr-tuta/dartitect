# Observabilidade

[English](observability.md)

## Padrões seguros

Crie `ObservabilityRuntime` explicitamente. Logging de desenvolvimento é o
padrão; reporting/tracing remotos exigem fornecedor explícito na composição.
Não use telemetria global.

## Política de dados

Sanitize antes de cada destino. Não registre authorization, cookies, tokens,
passwords, bodies, headers, queries, DSNs, identidade ou paths identificadores.
Error/fatal não são descartados por sampling. Falhas de destino ficam isoladas.

## Tracing

Aceite somente `traceparent` W3C válido; encaminhe `tracestate` opcional;
baggage fica desligada. Termine cada span uma vez em `finally`. Entre isolates,
transfira somente contexto validado.

## Erros

`Err<F>` esperado permanece estado. Crashes podem ser reportados uma vez com
mechanism, handled, fingerprint e attributes sanitizados e então relançados.

## Eventos reativos sem payload

`ReactiveOwner` e `MutationCommand` podem emitir `ReactiveChangeEvent` para um
`ReactiveObserver` injetado. Eventos contêm somente source/kind fixos, uma
identidade `ChangeCause` exata registrada na composição, revisões monotônicas,
duração monotônica e quantidade de listeners. Nunca contêm valores de domínio,
keys de entity ou idempotência, mensagens de erro, stack traces ou identidade.

Use `ReactiveJournal` somente como ring diagnóstico opt-in em memória. A
capacidade padrão é 200, entradas antigas são sobrescritas e o dispose limpa o
ring de forma terminal. Declare ownership ao registrá-lo. Falha de observer é
reportada uma vez, desabilita o observer e não muda o estado do runtime nem a
exceção vista pelo chamador.

```dart
final journal = ReactiveJournal();
final owner = ReactiveOwner(
  observer: ReactiveObserverRegistration.owned(
    journal,
    dispose: journal.dispose,
  ),
);
```

Para um destino de telemetria, injete `ReactiveObserverLoggerAdapter`. Ele
emite somente a mensagem fixa `reactive.change` e fatos allowlisted pelo
`ObservabilityRuntime`; a redaction normal roda novamente antes de cada sink.
Uma integração Sentry é a mesma cadeia terminando em `SentryLogSink`, cujo Hub
permanece borrowed. Não há persistência ou destino de rede por padrão.

## Protocolo diagnóstico local versionado

O protocolo diagnóstico v1 é separado de payloads de telemetria. Ele cobre
categorias fixas de owner, node, command, resource, family, effect, sync e
isolate usando apenas phases fixas de lifecycle, IDs opacos locais ao processo,
sequência monotônica, generation e revision. O decoder exato rejeita campos
desconhecidos. Não derive IDs de users, entities, operations, routes, queries ou
identificadores do provider.

Injete um `DartitectDiagnosticReporterRegistration` em um
`DartitectDiagnosticsEmitter`. O `DartitectDiagnosticBuffer` bounded é local e
somente em memória; dispose limpa todas as referências retidas. Falha e
reentrância do destino são isoladas por `SafeDartitectDiagnosticReporter`.
Detail pode ficar off, somente lifecycle ou topology local completa sem mudar o
comportamento da aplicação. A superfície de construção/reporting é
experimental conforme ADR 0034; não existe exporter remoto nem hook Flutter
global por padrão.

## Flutter e fornecedores

Instale um `FlutterErrorBinding`, encadeie/restaure handlers e evite recursão.
Adapters Sentry tomam um Hub inicializado pelo consumidor e nunca o fecham.
