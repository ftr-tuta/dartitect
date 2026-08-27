# dartitect_sync

[English](README.md)

## Propósito

Primitivas de sincronização Dart puro e neutras de provider para o Dartitect. O
consumidor define datasets, dependências, checkpoints, leases, retry/conflito e
adapters. O engine não importa Flutter, HTTP, armazenamento nem scheduler.

Cada entrypoint foreground ou headless cria e descarta seu próprio grafo owned.
Somente dados de comando validados atravessam isolates.

## Uso

Defina um `SyncDataset` por dataset com autoridade local, valide dependências
com `SyncDependencyGraph`, injete portas de checkpoint e lease opcional e
aguarde `engine.start().done`. Falhas esperadas retornam `Err`; exceções
inesperadas preservam a stack em `SyncRunTerminalException`, cujo report separa
application do dataset, checkpoint, journal, release do lease e cleanup.
Inspecione esse receipt antes de qualquer retry. Veja o
[exemplo executável](example/dartitect_sync_example.dart).

## Política do consumidor

A aplicação é dona de transações locais, mapeamento remoto, idempotência, retry,
resolução de conflitos, autenticação, agendamento, validação do payload,
deduplicação durável entre processos e recursos de provider. Stores de
checkpoint devem usar o fencing token recebido para rejeitar um lease obsoleto.
Quando há lease, cada `SyncDatasetContext` carrega `SyncAuthority`: chame
`ensureAuthority()` imediatamente antes do commit local e passe `fencingToken`
na mesma transação atômica do storage. Um Store que não consegue comparar e
commitir o token não recebe garantia de fencing apenas por usar o engine.
