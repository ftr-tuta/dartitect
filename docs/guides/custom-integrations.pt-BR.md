# Integrações customizadas

[English](custom-integrations.md)

## Objetivo

Integre banco, cliente HTTP, observabilidade, cache, fila ou outra ferramenta
sem exigir suporte oficial. Isole o fornecedor atrás de contratos pequenos da
aplicação.

## Adapter de ownership

Use `ResourceOwner` quando o callback de disposal vive na composição ou
implemente `AsyncDisposable` quando o adapter encerra de forma assíncrona:

```dart
final resources = ResourceOwner(label: 'session');
final client = resources.own(
  VendorClient(configuration),
  (value) => value.close(),
  label: 'Vendor client',
);
```

Marque borrowed explicitamente e não os registre para disposal. Descarte
consumidores/watchers antes do fornecedor.

## Eventos de arquitetura

Aceite `ArchitectureObserver` com `NoOpArchitectureObserver` por padrão. Emita
aquisição, release, falha e uso após disposal. Falha do observer não altera o
comportamento.

## Logs e erros

Implemente `LogSink` e/ou `ErrorReporter`. Converta apenas campos já sanitizados
e aplique redaction novamente se o fornecedor acrescentar contexto. Nunca mapeie
bodies, headers, queries, credenciais, DSNs, identidade ou paths.

```dart
final class VendorLogSink extends LogSink {
  VendorLogSink(this.client);
  final VendorClient client; // borrowed

  @override
  Future<void> emit(LogEvent event) => client.write(
    level: event.level.name,
    message: event.message,
  );
}
```

## Tracing

Implemente `Tracer` e retorne `Span` com `end` idempotente. Mapeie allowlist
mínima, aceite somente contexto W3C válido e finalize uma vez em `finally`.
Propagação do fornecedor é opt-in.

## Dados do consumidor

Entidades, schemas, credenciais, DSNs, endpoints, chaves, código gerado,
migrations e configuração pertencem ao consumidor. Adapters recebem objetos já
configurados; não carregam segredos nem inicializam globals.

## Testes

Use fixture real quando lifecycle/lock/geração importam e fake determinístico
quando haveria rede. Cubra falha de acquire, config parcial, concorrência,
cancelamento, shutdown exato, borrowed lifetime, redaction e zero resíduos.

## Propondo adapter oficial

Um PR reutilizável inclui pacote opcional isolado, testes contra SDK real, docs
English/pt-BR, exemplo, rationale de versão/dependência, revisão de licença e
advisory, snapshot de API e atualização das skills. Suporte oficial é decisão de
maintainers; integração customizada do consumidor continua válida.
