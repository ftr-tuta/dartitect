# Dartitect Isolates

[English](README.md)

## Objetivo

Workers de isolate tipados e vinculados a uma geração, com readiness explícito,
ACKs correlacionados, heartbeat, deadline por request, crash/exit e safe-stop.

O protocolo versão 2 separa o request ID visível ao caller de um nonce de
correlação monotônico e local à geração. Um ID público só pode ser reutilizado
depois do terminal anterior; envelope tardio do nonce antigo é descartado e não
conclui a request nova. `accepted` e `result` podem ser aguardados de forma
independente sem erro não observado no Future irmão.

## Quando usar

Use `IsolateWorker<P, R, F>` quando um workload Dart/Flutter nativo precisar de
um worker owned e protocolo tipado bounded. O handler retorna `Result<R, F>`
para falhas esperadas; crashes remotos inesperados preservam seu stack remoto.

## Ownership

O chamador possui o supervisor. Cada receptor monta seu próprio grafo. Somente
valores transferíveis validados cruzam a fronteira; clients, Stores, ViewModels,
subscriptions, timers e owners nunca cruzam. Chame `safeStop()` no teardown
reverso; termination forçada é apenas fallback após deadline.

Payloads, falhas esperadas e resultados de sucesso são copiados segundo as
regras de transferência de isolates do Dart. Valide um DTO versionado na
fronteira; não use o protocolo como framework de serialização nem esconda o
custo da cópia.

## Testes

Use o harness com isolate real de `dartitect_testing` para ACK, resultado/falha,
deadline, crash e zero requests residuais. Execute `dart test` no package.

## Limitações

Este pacote não é scheduler, process manager, registry global, framework de
serialização ou policy de restart infinito. Web não é declarado até existir um
contrato equivalente testado.
