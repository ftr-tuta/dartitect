# Adapters

[English](adapters.md)

## Composição

Crie adapters no composition root de app/sessão/isolate. Implementações de
infraestrutura satisfazem contratos do domínio/aplicação. Nenhum client, Store,
Hub ou config global pertence ao Dartitect.

## Dio

Separe falhas de cancelamento, transporte, HTTP e config. Instrumente apenas
método/protocolo/status. Propague via W3C configurado e rejeite duplicação com
`sentry_dio`.

## ObjectBox

O consumidor possui entidades/modelo gerado. Feche watchers/queries antes do
Store. Teste com fixture gerada real. Não edite gerados, assuma web nem envie
Store entre isolates.

## Sentry

Tome borrowed um Hub inicializado pelo consumidor. Nunca inicialize, configure
ou feche. Teste com Hub fake e zero rede.

## Adapters reutilizáveis

Uma proposta exige pacote isolado, testes reais, docs, rationale de dependência,
licença compatível e atualização das skills.
