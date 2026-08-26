# Comandos, resultados e efeitos

[English](commands-results-effects.md)

## Falhas esperadas

Retorne `Result<T, F>` para falha esperada de domínio/aplicação. Trate `Ok<T>` e
`Err<F>`. Não converta exceção arbitrária em sucesso ou falha esperada sem relação.

## Matriz de scheduling de commands 1.0

`Command0<T, F>`, `Command1<A, T, F>` e o dedicado
`KeyedCommand1<K, A, T, F>` usam os mesmos contratos Dart puros de lane. Toda
FIFO retida, lane de concorrência configurada e coleção de keys ativas tem
limite positivo explícito.

| Policy | Limite e admissão | Chamada durante busy | Ordem e publicação terminal |
| --- | --- | --- | --- |
| `reject` (padrão) | Uma execução running | `rejected(busy)` | A execução aceita publica seu terminal |
| `join` | Uma execução running | Retorna o mesmo future; commands com argumento só juntam argumento igual na mesma key, caso contrário `rejected(busy)` | Uma execução e uma identidade terminal |
| `drop` | Uma execução running | `dropped`; não inicia, enfileira nem troca estado retido | Somente a execução running pode publicar |
| `sequential(maxQueue)` | Uma running mais FIFO positiva bounded; fila padrão 64 | Enfileira FIFO ou `rejected(queueFull)` | Toda execução aceita roda na ordem de admissão |
| `restartLatest` | Uma generation publicável; trabalho superseded ainda pode drenar cooperativamente | Cancela/substitui generations anteriores e inicia uma nova | Somente a última generation aceita pode publicar |
| `concurrent(maxConcurrent)` | Limite running positivo; padrão 4 | Inicia dentro do limite ou `rejected(concurrentLimit)` | Um terminal publica somente se seu execution ID não for anterior ao terminal retido |
| `keyed(perKey, maxConcurrent)` | Limite positivo de keys ativas, padrão 4; uma policy bounded não-keyed por key | Aplica o resultado por key ou `rejected(keyLimit)` para key nova | Keys agendam independentemente; crash para somente sua key |

## Outcomes, cancelamento e crashes de command

Cada chamada distinta aceita recebe execution ID monotônico. O state observável
é exaustivo (`idle`, `running`, `success`, `failure` esperada, `cancelled` ou
`crashed`) e informa contagens running/queued e IDs da última aceita e do
terminal retido. Os resultados da chamada permanecem separados:

- `succeeded(value)` e `failed(F, stack)` são terminais de domínio aceitos;
  `Err<F>` nunca é reportado como erro inesperado.
- `rejected(reason)` e `dropped` não iniciaram e nunca substituem o terminal
  retido.
- `cancelled(reason)` é controle de fluxo, nunca `F`. Cancelamento é
  cooperativo: o caller conclui prontamente, a action observa o
  `CancellationSignal` owned pela lane e o disposal do owner ainda drena a
  action subjacente.
- Exceção inesperada é reportada no máximo uma vez para aquela execução, fica
  retida como crash e é relançada com stack original. Ela para uma lane ou lane
  keyed até `resume()` depois que o trabalho running terminar.

Conclusão tardia de generation cancelada, superseded, concorrente mais antiga
ou disposed não publica state nem notifica listeners. `reset()` limpa terminal
retido somente com command totalmente idle. Disposal é idempotente: fecha
admissão, rejeita fila como disposed, pede cancelamento, drena actions running,
limpa mappings de futures Flutter e não notifica após disposal.

## Matriz de recursos reativos 1.0

Dados do recurso (`waiting`, `ready`, `failed` esperada ou `crashed`
inesperada) são independentes da temperatura upstream. Estados failed/crashed
podem reter dado nullable anterior explicitamente via `hasData`.

| Eixo/valor | Atividade da source | Retenção/backpressure | Regra terminal ou de recuperação |
| --- | --- | --- | --- |
| Temperatura `hot` | Uma sessão de source local à ativação está ativa | Snapshot retido; reads admitidos | Somente publicação da generation atual é aceita |
| Temperatura `warm` | Nenhuma sessão de source ou read está ativa | Snapshot anterior pode permanecer | Reativação abre nova sessão de source |
| Temperatura `cold` | Nenhuma sessão de source ou read está ativa | Snapshot e marcador stale são descartados | Ativação inicia nova generation |
| `alwaysHot` | `start()` ativa sem observers | Hot até disposal do owner | Somente disposal torna cold |
| `whileObserved` | Hot enquanto observation com ticker habilitado tem listener ou existe `ResourceLease` | Sem retenção warm | Liberação da última atividade torna cold |
| `keepWarm(duration)` | Mesma regra de atividade de `whileObserved` | TTL positivo retém snapshot warm; nova aquisição cancela timer | Expiração do TTL torna cold |
| `manual` | Somente `activate()` explícito inicia upstream | `deactivate(retainSnapshot: true)` é warm; `false` é cold | Leases/observers não sobrepõem controle manual |
| `everyEmission` | Uma read por vez | Preserva todo signal em backlog serial; use somente com source externamente bounded | Fechamento limpa signals pendentes e cancela/drena a read ativa |
| `coalesceMicrotask` | Uma read por vez | No máximo uma microtask agendada e uma repetição dirty durante busy | Signals dentro da fronteira são combinados |
| `coalesceFrame` | Uma read por vez | No máximo um frame agendado e uma repetição dirty durante busy | Signals dentro do frame são combinados |
| `latestWhileBusy` (padrão) | Uma read por vez | No máximo uma repetição dirty durante busy | Burst vira a read ativa mais uma última repetição |

Cada `ReactiveSource.open()` cria sessão nova que possui watcher, subscription,
query ou cursor e toma providers injetados borrowed. Um `Err<F>` esperado de
read publica `ResourceFailed` sem reportar nem parar a sessão hot. Falha esperada
de open suspende após publicar failure. Erro inesperado de open/read/stream
publica `ResourceCrashed`, reporta uma vez por generation, fecha a sessão e
suspende warm ou cold conforme retenção. Somente `retry()` explícito retoma e
abre generation nova.

Uma `ReactiveObservation` pertence ao caller e contribui atividade somente com
listener e ticker habilitado. `LiveResource.addListener()` passivo não ativa
upstream. `ResourceLease` é invalidada pelo owner, idempotente e mantém policies
automáticas hot até sua liberação aguardável reconciliar a temperatura. Falhas
de listener e reporter ficam isoladas do state. Retenção idle de
`ResourceFamily` é limitada por TTL positivo e budgets não negativos de
quantidade/peso; entries leased, observed ou hot não são removidas.

Disposal do recurso fecha admissão, invalida leases e observations, pede
cancelamento cooperativo, drena reads, cancela subscription de signals, fecha a
sessão local à ativação, descarta snapshot, limpa listeners/bindings/timers e
agrega falhas independentes de cleanup. Disposals concorrentes compartilham uma
conclusão e toda publicação tardia é rejeitada.

## Efeitos

Use `EffectChannel<E>` owned somente para reações transitórias de UI tipadas e
imutáveis. Sua capacity positiva é bounded; overflow e emit após disposal
retornam resultados explícitos. Um consumidor lógico recebe cada efeito aceito
uma vez em FIFO. `EffectListener` toma o channel borrowed e chama o callback com
seu contexto montado atual; channel e ViewModel nunca retêm `BuildContext`.

Verdade de autenticação/sessão não é efeito. Dirija o shell pelo
`SessionStateController<S>` replayable, remova rotas autenticadas em
`SessionForcedLogout` e então drene/feche o graph antigo. Uma nova geração de
owner recebe channel novo e nunca herda efeitos pendentes da geração anterior.

## Matriz de testes

Cubra todas as policies, sucesso, falha esperada, rethrow, limites de fila/key,
busy/disposed, cancelamento, stale completion, reporting único, FIFO/overflow/
detach/falha do consumidor de efeitos, todos os estados de dados e temperaturas,
transições de ativação/lease/TTL, toda fronteira de backpressure, retry explícito,
logout durante navegação e zero recursos running, queued, effects pendentes,
observers, leases, timers, reads, sessões de source, families ou sessão após
disposal.
