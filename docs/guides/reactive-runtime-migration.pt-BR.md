# Adoção opt-in do runtime reativo

O entrypoint `package:dartitect_flutter/dartitect_flutter.dart` é a superfície
fina estável para `ViewModelHost`, `Command0`/`Command1`,
`ListenableSelector`, scope e binding de erros.

## Entrypoints

Importe `package:dartitect_flutter/dartitect_flutter_reactive.dart` apenas
quando uma feature adotar o grafo reativo owned, recursos, coleções ou builders
headless. O entrypoint headless nunca exporta Material; a apresentação owned
pelo consumidor combina os builders com widgets Material ou Cupertino.

## Ownership

Crie um owner reativo por fronteira explícita de composição de app, sessão,
rota ou background. Injete repositórios e adapters por construtor. Descarte
widgets e comandos primeiro; depois observações, queries e clients; por fim o
owner. Stores, clients e destinos de telemetria pertencentes ao consumidor
continuam borrowed e são fechados pelo consumidor.

## Grafo atômico

`ReactiveOwner` cria values e computeds identificados por chave tipada. Faça
toda escrita dentro de `owner.update`; updates aninhados participam da
transação externa e listeners executam somente após todos os computeds afetados
estabilizarem. Um crash de compute preserva o snapshot anterior, é reportado
pelo `ReactiveComputeReporter` injetado e é relançado com o stack trace
original.
Cada node implementa diretamente o `ValueListenable<T>` do Flutter. A igualdade
é local ao node e usa `==` por padrão; forneça callback explícito quando a regra
de mudança significativa do domínio for diferente.

Descarte o owner para remover todos os edges e listeners. Um owner descartado é
terminal e rejeita leituras, criação de nodes, registro de listeners e escritas.

## Lifecycle de recursos

O estado de dados (`waiting`, `ready`, `failed` ou `crashed`) é independente da
temperatura do upstream (`hot`, `warm` ou `cold`). Escolha uma
`ActivationPolicy`, retenha lifetime com `ResourceLease` e permita que
`ReactiveObservation` pause atividade quando `TickerMode` estiver desabilitado.
Recursos warm retêm o último dado conhecido sem upstream ativo; recursos cold
descartam ambos.

Use `AsyncLifecycleBarrier` ao redor do trabalho assíncrono da fonte. O dispose
fecha admissão primeiro, solicita cancelamento cooperativo, drena operações
admitidas e rejeita toda publicação stale antes de liberar o grafo.

## Sources live e backpressure

Implemente `ReactiveSource<T, F>` como factory de sessões locais à ativação.
Cada sessão possui a subscription, query ou cursor que cria; Stores e clients
injetados continuam borrowed. `LiveResource<T, F>` faz a primeira leitura
autoritativa e reabre uma sessão nova a cada geração hot.

O padrão `SourceBackpressure.latestWhileBusy` executa uma leitura e memoriza no
máximo uma repetição dirty enquanto está ocupado. Escolha `everyEmission`,
`coalesceMicrotask` ou `coalesceFrame` somente quando essa fronteira fizer parte
do contrato da feature. `Err<F>` esperado preserva o último dado conhecido. Um
crash inesperado é reportado uma vez, suspende e fecha a source e só retoma por
`retry()` explícito. O dispose cancela e drena o trabalho admitido antes de
fechar a sessão.

Use `FutureReactiveSource`, `StreamReactiveSource`,
`ListenableReactiveSource` ou `ValueListenableReactiveSource` ao adaptar
primitivos nativos. Cada ativação hot cria sessão/subscription nova. Streams
carregam eventos `Result<T, F>` tipados; um erro real do stream continua crash
inesperado com stack original em vez de ser convertido para `F`.

## Invalidation e refresh causal

Crie grupos tipados com `ReactiveOwner.invalidationGroup<K>()` e associe
instâncias `LiveResource` borrowed às keys da feature. Cada invalidation do
grupo possui revisão monotônica. Um recurso hot inicia trabalho bounded da
source imediatamente; um recurso warm marca o snapshot retido stale e atualiza
ao reativar; um recurso cold não inicia trabalho nem retém snapshot stale. O
dispose do owner ou do recurso desfaz o registro sem descartar o outro.

Use o tipo de refresh que declara o ponto de conclusão realmente exigido pela
UI:

- `RemoteRefresh<T, F>` conclui com a ação remota;
- `LocalCommitRefresh<R, F>` conclui com `LocalCommitReceipt<R>`;
- `ObservedLocalRefresh<T, R, F>` conclui somente depois que uma source publica
  `ObservedValue<T, R>` com a revisão exata do receipt.

A forma observada exige timeout positivo e callback do consumidor que o mapeia
para `F`. Waiters são indexados pela revisão tipada, timers pertencem à operação
e timeout/dispose removem ambos sem alterar o dado autoritativo. Os pontos de
conclusão têm tipos de resultado estáticos distintos e não podem ser trocados
acidentalmente.

## Families de resources bounded

Crie uma `ResourceFamily<K, T, F>` numa fronteira explícita de composição e
injete uma factory de key para `LiveResource`. Keys iguais compartilham somente
dentro daquela family; outra family sempre cria resource independente. Adquira
um `FamilyLease` para cada retenção do consumidor e libere-o de modo idempotente.

`FamilyCachePolicy<K, T>` limita retenção idle com TTL positivo,
`maxIdleEntries` e `maxIdleWeight`. `weightOf` recebe a key tipada e o valor
retido opcional. Quando os limites exigem eviction, entram primeiro entradas
expiradas, depois menor custo de recriação, acesso menos recente e ordinal
estável de criação. Leases ativas, observers e resources hot nunca sofrem
eviction. Uma entrada maior que todo o orçamento de peso é descartada
diretamente sem remover entradas válidas do cache.

`prewarm(key, duration)` pertence à family: retém a entrada, possui observation
e timer temporários e então libera os três. Invalidation delega às mesmas regras
tipadas de `InvalidationGroup`. Eviction remove a entrada do índice antes do
dispose assíncrono, então reacquire cria nova generation mesmo enquanto a antiga
drena. Falhas de dispose continuam visíveis como cleanup failures agregadas e
nunca reinserem a entrada que falhou.

## Live collections incrementais

`LiveCollection<K, T>` mantém item nodes estáveis e separa seus sinais: `keys`
muda somente em membership/reorder, `length` somente na quantidade,
`item(key)` somente naquele valor projetado e `changes` emite fatos estruturais
tipados. Cada update seleciona `replaceAll`, `diffByKey` ou `versionedByKey`
explicitamente; não existe threshold oculto por tamanho.

A política versionada mantém cache `key -> version -> projection`, então versão
inalterada reutiliza sua projeção. A collection valida todas as keys e calcula o
próximo cache completo antes da publicação. Duplicate key ou crash de projection
preserva order, nodes, cache, revision e notifications anteriores. Membership,
reorder e valores de item ficam visíveis como um único batch síncrono.

Nodes removidos publicam tombstone (`isPresent == false`) e permanecem estáveis
enquanto têm listeners ou a retenção warm configurada não expirou. Uma key
reattachada reutiliza o node; expiry ou dispose da collection cancela timers e
o desanexa. Para ObjectBox, `ObjectBoxVersionedProjection` recebe callbacks de
ID, version e projection pertencentes ao consumidor—entities e model code
gerado continuam fora do Dartitect.

Projection permanece inline a menos que `updateProjected` receba
`ProjectionExecution.background` e executor injetado. O isolate principal
calcula keys/versions, envia somente `CollectionProjectionInput` alterados e
confirma um conjunto completo de `CollectionProjectionOutput` apenas se sua
geração continuar atual. Crash, cancelamento, dispose, key ausente/duplicada ou
conclusão stale preserva o snapshot estável da collection.
A geração atual expõe `CollectionProjectionStatus.crashed` com a stack original
até uma projeção posterior explícita concluir; não existe retry automático.

`IsolateProjectionExecutor` possui e drena workers genéricos. Para um Store
ObjectBox real, use `ObjectBoxProjectionExecutor` sobre `Store.runAsync` ou
`Query.findAsync`; crie graph/query do worker a partir de configuração
transferível e feche em `finally`. O Store original permanece borrowed e fecha
somente depois do teardown da collection e do executor.

## Selectors, debounce e páginas local-first

Use `ReactiveSelector<S, T>` quando um valor derivado precisa existir fora de um
widget. Ele assina um `Listenable` borrowed, avalia cada sinal da source e
notifica downstream somente quando sua igualdade configurável indica mudança.
O selector possui essa subscription e a remove no dispose.

`DebouncedReactiveValue<T>` assina um `ValueListenable` borrowed, possui um
único timer injetado de quiet period e publica somente o último valor distinto.
`flush()` é explícito; dispose cancela timer pendente sem publicar valor stale.

`PagedLiveResource<C, K, T, F>` mantém dados remotos fora do estado de
apresentação. O request injetado retorna um `PageBatch`; o resource deduplica por
callback de key do consumidor e passa um `PageWrite` à transação local
pertencente ao repository. A transação retorna `PageWriteReceipt`, mas o cursor
só avança quando o `LiveResource<PagedLocalSnapshot<K, T>, F>` borrowed publica
a revisão exata do receipt. A `LiveCollection` exposta muda somente a partir
desse snapshot local.

Refresh usa command lane join, load-more descarta chamadas reentrantes e search
usa restart-latest. O cancelamento é verificado antes da escrita local, portanto
uma geração cooperativa stale de search não altera banco nem collection. Falhas
esperadas de request, write ou timeout de observation preservam os últimos dados
locais e o cursor válido. O stream síncrono `timeline` expõe as fases de request,
response, commit local, observation local e conclusão sem reter transcript
ilimitado.

## Mutations offline-first e recovery de outbox

`MutationCommand<A, K, T, F>` agenda mutations sequencialmente por key da
entity. O `MutationOutboxStore` injetado possui a única escrita local
autoritativa: `applyLocalAndEnqueue` deve alterar dados de domínio e persistir a
`OutboxOperation` numa transação. Dartitect nunca aplica patch em lista de
apresentação na memória nem define entities, schema de outbox, endpoints ou
regras de conflito do consumidor.

Cada operação carrega idempotency key não vazia, no escopo do consumidor,
reutilizada em todas as tentativas at-least-once. Sucesso remoto torna-se
`committed/synced` somente após o store persistir esse acknowledgement. Falha
esperada é mapeada por `MutationFailurePolicy` para queued/pending, rejected,
conflicted ou uncertain. Alterações queued e uncertain não sofrem rollback
automático. Rejeição definitiva pode ser seguida pela transação explícita
`compensate`.

Retry é manual por padrão. `RetryClassification.transient` torna uma classe de
falha opt-in para retries exponenciais bounded, preservando operação e
idempotency key. Crash inesperado de delivery é reportado uma vez, relançado,
marca a operação durable uncertain quando a entrega pode ter confirmado e para
somente a lane daquela key. Audite estado do provider/repository, persista uma
decisão pending deliberada, chame `resume(key)` e então faça retry.
`recoverPending()` numa sessão nova deduplica idempotency keys e drena somente
registros pending; uncertain permanece intocado até essa decisão explícita.

Para ObjectBox, coloque as duas escritas de entities do consumidor dentro de
`ObjectBoxMutationTransaction.run`. Sua transação síncrona converte `Err` tipado
em rollback e retorna a mesma falha; crashes inesperados também revertem e são
relançados. O Store permanece borrowed.

## Diagnóstico causal sem payload de domínio

Chamadas externas de `ReactiveOwner.update` e operações terminais de
`MutationCommand` podem publicar um `ReactiveChangeEvent`. O evento é limitado
a source, tipo do resultado, uma `ChangeCause` static previamente registrada,
revisões, duração monotônica e quantidade de listeners. Registre causas
customizadas uma vez no composition root e passe a identidade exata; causas
reconstruídas ou dinâmicas são rejeitadas antes de qualquer alteração de estado.

Observers são injetados como registrations explicitamente owned ou borrowed.
Use o `ReactiveJournal` bounded e somente em memória para diagnóstico local ou
`ReactiveObserverLoggerAdapter` para observabilidade sanitizada. Falha do
observer é isolada e reportada uma vez; depois ele é desabilitado. Eventos e o
journal nunca armazenam payload de domínio, keys, texto de erro ou identidade.

## Builders headless e apresentação do consumidor

O entrypoint reativo fornece `ReactiveValueBuilder`, `LiveResourceBuilder`,
`LiveCollectionBuilder` e `PagedLiveBuilder` sem importar Material. Cada widget
toma seu input borrowed e possui somente listener ou `ReactiveObservation`.
`TickerMode` desabilita essa observação e todos os rebuilds offscreen; unmount
desanexa sincronamente, enquanto rota/composition root drena e descarta o
resource borrowed fora de `build`.
O hook opcional `onBuild` recebe somente `FlutterBindingBuildEvent`: tipo do
binding, contagem monotônica, duração do callback, handles locais e estado do
ticker. Falhas do observer são isoladas e valores, keys, queries, identidades e
mensagens de erro nunca são incluídos.

Builders de collection observam somente estrutura de keys. Renderize cada
`LiveItem` com `ReactiveValueBuilder` para uma mudança não reconstruir a lista
inteira. `ValueKey` estável e `findChildIndexCallback` preservam State da linha
em reorder. Callbacks e efeitos one-shot pertencem à rota e nunca são repetidos
pelo builder.

Telas Material e Cupertino renderizam waiting/ready/falha/crash na aplicação
sem converter failures para string automaticamente. Use live regions Semantics
estáveis, controles acessíveis por teclado, text scaling e callbacks de
retry/refresh/load-more pertencentes à rota. Os workloads de referência
demonstram esse limite e descartam o paged resource antes da source local.

Os entrypoints avançados são preparados em `1.0.0-rc.2`; mudanças são
adicionadas em incrementos revisados e permanecem opt-in durante toda a linha
candidata.
