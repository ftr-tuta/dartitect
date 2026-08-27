# dartitect

[English](README.md)

## Objetivo

Primitivos Dart puros para falhas esperadas tipadas, ownership determinístico de
lifecycle e eventos opcionais de arquitetura. Não há dependências de runtime
fora do SDK Dart.

## Quando usar

Use em limites de domínio/aplicação e composition roots quando lifetime e falha
esperada precisam aparecer nos tipos. Não é container de DI, service locator,
gerenciador de estado ou logger.

## Quando não usar

Não adicione apenas para embrulhar valores ou exceções comuns sem contrato de
recuperação tipado. Ele não fornece UI, storage, transporte, telemetria ou
container de runtime.

## Combinações recomendadas

Combine com `dartitect_flutter` somente na presentation Flutter, com
`dartitect_observability` para contratos neutros de telemetria e com adapters de
provider apenas na composição de infraestrutura. Consulte o
[guia de seleção do ecossistema](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.pt-BR.md)
e as [receitas de implementação](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.pt-BR.md).

## Instalação

Este candidato não está publicado no pub.dev. Declare
`dartitect: 1.0.0-rc.2` e siga o
[guia de consumo do candidato Git](../../docs/guides/git-candidate-consumption.pt-BR.md)
para fixar o pacote e suas dependências Dartitect transitivas na tag protegida.

## Exemplo mínimo

```dart
import 'package:dartitect/dartitect.dart';

Future<Result<int, String>> loadCount() async => const Ok(3);

Future<void> main() async {
  final owner = ResourceOwner(label: 'session')
    ..own(_Connection(), (value) => value.dispose());
  final result = await loadCount();
  switch (result) {
    case Ok(:final value): print(value);
    case Err(:final failure): print('Esperada: $failure');
  }
  await owner.disposeAsync();
}

final class _Connection {
  void dispose() {}
}
```

## Tour da API pública

- `Result<T, F>`, `Ok`, `Err` e `ResultOperations` modelam resultados esperados.
- `Disposable` e `AsyncDisposable` definem contratos pequenos de lifecycle.
- `ResourceOwner` descarta em ordem reversa e agrega falhas em
  `ResourceCleanupException`.
- `ArchitectureObserver`, `ArchitectureEvent` e `NoOpArchitectureObserver`
  expõem sinais opcionais e não fatais.
- `CancellationSource`/`CancellationSignal`, `CommandLane` e
  `KeyedCommandLane` oferecem scheduling tipado e bounded sem Flutter.
- `ProjectionExecution` mantém projection inline por padrão.
  `IsolateProjectionExecutor<P, R>` é uma opção background explícita por task
  para requests/results transferíveis; cancelamento descarta resultado stale e
  dispose drena workers para concluir cleanup local ao isolate em `finally`.
- `MutationCommand<A, K, T, F>` executa mutations local-first em lanes
  sequenciais bounded por key. `MutationOutboxStore` mantém a transação atômica
  de alteração local/outbox pertencente ao consumidor; `OutboxOperation`
  preserva uma idempotency key entre entregas at-least-once e restart da sessão.
- `CommitDisposition`, `EntitySyncState`, `MutationFailurePolicy` e
  `RetryClassification` separam resultados queued, rejected, conflicted e
  uncertain. Retry automático é opt-in e bounded; compensation e resume da
  lane após crash são explícitos.
- `ChangeCause`, `ReactiveChangeEvent` e `ReactiveObserver` expõem somente
  causas static registradas, revisões, duração e quantidade de listeners.
  `ReactiveJournal` é um ring opt-in somente em memória com capacidade padrão
  200; `SafeReactiveObserver` isola e desabilita um destino que falha.

## Ownership

O composition root decide se um valor é owned ou borrowed. Registre apenas
owned values e descarte dependentes antes das dependências. Não transfira
recursos vivos entre isolates.

## Limitações

`Result` não converte exceções inesperadas em sucesso/falha esperada.
`ResourceOwner` não infere ownership nem substitui regras do fornecedor.
`MutationCommand` não torna atômico um repository sem transação nem promete
exactly-once; schema e transport do consumidor aplicam o escopo documentado de
idempotência. Eventos reativos nunca carregam payload de domínio, key da
operação, texto de erro, identidade ou histórico persistido. Execução
background nunca é selecionada automaticamente e requer plataforma com spawn
de isolates, callbacks e valores transferíveis.

## Extensão

Implemente os contratos públicos pequenos. Mantenha SDKs e tipos de negócio na
aplicação ou em um pacote adapter isolado.

## Testes

Execute `dart test`. Cubra rollback atômico local/enqueue, queue offline,
duplicatas at-least-once, recovery por audit após crash e compensation
explícita. `dartitect_testing` oferece probes e harnesses sem reexportar um test
runner.

## Links

Veja o [guia do workspace](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/getting-started.pt-BR.md), a
[política de API](https://github.com/ftr-tuta/dartitect/blob/main/VERSIONING.adoc) e o [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
