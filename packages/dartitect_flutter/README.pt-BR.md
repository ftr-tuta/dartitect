# dartitect_flutter

[English](README.md)

## Objetivo

Primitivos Flutter finos para ViewModels owned/borrowed, comandos async,
rebuilds selecionados, scope de composição estável e erros Flutter de foreground.

## Quando usar

Use quando `ChangeNotifier`, `Listenable` e lifecycle de widgets são suficientes,
mas ownership e estado de comandos precisam ser explícitos. Não substitui
navegação, widgets ou camada de domínio.

A library estabelecida `dartitect_flutter.dart` permanece fina. APIs reativas
headless avançadas entram pelo entrypoint opt-in
`dartitect_flutter_reactive.dart`. A renderização Material permanece na
aplicação consumidora.

## Quando não usar

Não importe em código de domínio/aplicação Dart puro. Não adote o entrypoint
reactive quando as APIs finas de `ChangeNotifier`, command e
lifecycle de ViewModel já atendem à feature.

## Combinações recomendadas

Combine o entrypoint fino com `dartitect`; adicione reactive para resources
hot/warm/cold e páginas de autoridade local. Construa a presentation Material
ou Cupertino na aplicação. Adicione adapters de provider atrás de repositories. Consulte o
[guia de seleção do ecossistema](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.pt-BR.md)
e as [receitas de implementação](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.pt-BR.md).

## Instalação

Este candidato não está publicado no pub.dev. Declare
`dartitect_flutter: 1.0.0-rc.1` e use o
[guia de consumo do candidato Git](../../docs/guides/git-candidate-consumption.pt-BR.md)
para fixá-lo junto com `dartitect` na tag protegida.

## Exemplo mínimo

```dart
final command = Command0<int, String>(
  () async => const Ok(42),
  concurrency: const CommandConcurrency.join(),
);
final execution = await command.execute();
await command.disposeAsync();
```

Veja `example/dartitect_flutter_example.dart` para um exemplo executável.

## Tour da API pública

- `Command0<T, F>`, `Command1<A, T, F>` e o dedicado
  `KeyedCommand1<K, A, T, F>` expõem policies bounded reject, join, drop,
  sequential, restart-latest, concurrent e por key. O state inclui contagens
  exatas running/queued e IDs de execução aceita/terminal.
- `ViewModelHost.create` possui o valor e chama seu `start` opcional uma vez sem
  atrasar o primeiro build; `ViewModelHost.value` apenas toma borrowed.
- `ListenableSelector` reconstrói somente quando a seleção muda e desanexa
  enquanto o `TickerMode` ao redor está desabilitado.
- `DartitectScope<T extends DartitectScopeValue>` marca uma fronteira explícita
  de composição. Seu `scopeIdentity` opaco precisa permanecer idêntico durante
  a vida do inherited widget; ele não é service locator.
- `EffectChannel<E>` é FIFO bounded de consumidor único, owned por uma geração
  explícita de aplicação/sessão/rota. Só `EffectListener` usa o contexto montado
  atual. `SessionStateController<S>` mantém estado replayable de shell/logout
  separado de efeitos one-shot.
- `FlutterBindingBuildEvent` relata somente tipo de binding, contagem, duração,
  handles locais e ticker; nunca carrega payload de domínio.
- `FlutterErrorBinding` encadeia/restaura handlers com `ErrorReporter` injetado.
- O entrypoint reativo opt-in expõe `ReactiveOwner`, transações `update`
  atômicas, values/computeds por chave tipada que implementam diretamente
  `ValueListenable<T>`, igualdade por node e diagnósticos determinísticos.
  Cada update externo pode emitir um `ReactiveChangeEvent` sanitizado por um
  observer explicitamente owned ou borrowed; causas customizadas precisam ser
  identidades static previamente registradas.
- `ResourceLifecycle` separa dados da temperatura hot/warm/cold;
  `ReactiveObservation` e `AsyncLifecycleBarrier` limitam atividade e teardown.
- `LiveResource<T, F>` abre uma sessão `ReactiveSource` local à ativação e
  aplica backpressure explícito por emissão, microtask, frame ou
  latest-while-busy. O padrão permite no máximo a leitura ativa e uma repetição.
- `FutureReactiveSource`, `StreamReactiveSource`, `ListenableReactiveSource` e
  `ValueListenableReactiveSource` adaptam primitivos async/nativos em sessões
  novas por ativação sem tomar ownership de listenables borrowed.
- `InvalidationGroup<K>` compartilha invalidations tipadas: recursos hot fazem
  refresh, snapshots warm ficam stale até reativar e recursos cold não executam
  trabalho. `ReactiveOwner.invalidationGroup` possui o teardown do grupo.
- `RemoteRefresh`, `LocalCommitRefresh` e `ObservedLocalRefresh` codificam três
  pontos de conclusão distintos. A forma observada liga
  `LocalCommitReceipt<R>` a `ObservedValue<T, R>` com timeout tipado obrigatório.
- `ResourceFamily<K, T, F>` compartilha resources somente dentro de uma family
  owned. Valores `FamilyLease` explícitos retêm entradas ativas; entradas idle
  são limitadas por TTL, quantidade e peso com ordem estável por custo/LRU.
  `prewarm` possui sua observation e seu timer.
- `LiveCollection<K, T>` expõe sinais separados de keys, length, item e changes.
  Escolha `replaceAll`, `diffByKey` ou `versionedByKey` explicitamente; updates
  versionados reutilizam projeções e notificam somente nodes alterados. Itens
  removidos ficam como tombstones bounded enquanto observados ou warm.
  `updateProjected` continua inline por padrão; execução background explícita
  exige `ProjectionExecutor` injetado e publica somente outputs transferíveis
  da geração correspondente e não cancelada. Crash no worker preserva o
  snapshot e fica diagnosticável como `CollectionProjectionStatus.crashed` até
  uma projeção posterior explícita concluir.
- `ReactiveSelector<S, T>` deriva um valor headless com igualdade explícita;
  `DebouncedReactiveValue<T>` possui e cancela seu timer de quiet period
  injetado.
- `PagedLiveResource<C, K, T, F>` busca `PageBatch` remotos, remove keys
  duplicadas e os entrega à transação local pertencente ao consumidor. Sua
  `LiveCollection` muda e o cursor avança somente quando a source local borrowed
  observa a revisão exata do `PageWriteReceipt`. Refresh usa join, load-more
  descarta reentrância e search usa cancelamento restart-latest.
- `ReactiveValueBuilder`, `LiveResourceBuilder`, `LiveCollectionBuilder` e
  `PagedLiveBuilder` são headless, tomam inputs borrowed e observam somente com
  `TickerMode` habilitado. Rebuilds de estrutura e item continuam separados.
  O observer opcional de build recebe os mesmos fatos sanitizados do selector
  fino.

## Ownership

Crie ViewModels no limite de composição mais próximo. `.create` descarta;
`.value` nunca descarta o valor borrowed. Instale um binding e restaure no fim.

## Limitações

Mantenha `BuildContext` fora de ViewModels, services, repositories, domínio e
data. Falhas esperadas de comandos são estado e não são reportadas automaticamente.
Falhas esperadas de source preservam o último dado conhecido. Crashes de source
são reportados uma vez, fecham o upstream e exigem `retry()` explícito.

## Extensão

ViewModels podem implementar `Listenable`; reporting usa contratos
provider-neutral de `dartitect_observability`.

## Testes

Execute `flutter test`. Cubra busy/disposed, retry, stale completion, fan-out de
selectors, teardown de debounce, timelines causais de páginas, rethrow, rebuild
selecionado, pausa/resume de TickerMode, semantics, teclado, text scaling,
reorder keyed e chain/restore dos handlers.

## Links

Veja [comandos/resultados/efeitos](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/commands-results-effects.pt-BR.md),
[migração do runtime reativo](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/reactive-runtime-migration.pt-BR.md),
[composição/lifecycle/isolate](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/composition-lifecycle-isolates.pt-BR.md) e o [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
