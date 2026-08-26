# dartitect_dio

[English](README.md)

## Objetivo

Helpers opcionais de ownership, falhas tipadas, cancelamento, propagação W3C e
telemetria mínima sobre a API real do Dio.

## Quando usar

Use no composition root de infraestrutura que já escolheu Dio. Não importe Dio
ou este adapter em domínio, ViewModel ou presentation.

## Quando não usar

Não use quando a aplicação não escolheu Dio, quando se espera uma abstração HTTP
voltada ao domínio ou quando outro interceptor já fornece o mesmo tracing/capture.

## Combinações recomendadas

Combine com contratos de transporte da aplicação, `dartitect_observability`
para política neutra de telemetria e repositories offline-first somente após
definir o limite de transação local. Consulte o
[guia de seleção do ecossistema](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.pt-BR.md)
e as [receitas de implementação](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.pt-BR.md).

## Instalação

Este candidato não está publicado no pub.dev. Declare
`dartitect_dio: 1.0.0-rc.2` e use o
[guia de consumo do candidato Git](../../docs/guides/git-candidate-consumption.pt-BR.md)
para gerar o fechamento completo de overrides.

## Exemplo mínimo

```dart
final owner = DioOwner.create();
try {
  final response = await owner.dio.get<void>('/health');
  print(response.statusCode);
} finally {
  owner.dispose();
}
```

## Tour da API pública

- `DioOwner.create` possui/fecha; `DioOwner.value` toma borrowed.
- Variantes de `DioFailure` separam cancelamento, HTTP, transporte e config.
- `captureDioException` converte exceções em falhas tipadas de `Result`.
- `DartitectHeadersInterceptor` propaga somente contexto W3C configurado.
- Interceptors/instrumentation emitem atributos mínimos seguros.
- `ownCancelToken` registra cancelamento em `ResourceOwner`.
- `bindCancelToken` liga um `CancellationSignal` Dart puro a um token Dio
  compartilhável sem inverter ownership.

## Ownership

Crie o client no composition root de app/sessão/isolate. Descarte requests e
tokens antes do Dio owned. Clients borrowed são fechados pelo consumidor.

## Limitações

Telemetria inclui apenas método, protocolo e status—nunca bodies, headers,
queries, credenciais ou paths. Instrumentação Dartitect/`sentry_dio` duplicada
é rejeitada.

## Extensão

Adicione interceptors específicos na composição e exponha contratos do domínio.
Não esconda um Dio global atrás do Dartitect.

## Testes

Execute `dart test` com adapter mock e rede desativada. Cubra concorrência,
cancelamento, mapping, propagação, duplicação e disposal.

## Links

Veja [adapters](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/adapters.pt-BR.md),
[integrações customizadas](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/custom-integrations.pt-BR.md) e o [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
