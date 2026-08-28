# dartitect_modeling

[English](README.md)

## Finalidade

Primitivas de modelagem imutável em Dart puro, compatíveis com web. Importe
este package para optar por values, codecs JSON, projections ou mappers de
boundary. Cada capacidade exige sua própria annotation; schemas de providers e
a arquitetura de runtime do aplicativo continuam pertencendo ao consumidor.

## Collections imutáveis

`ImmutableValueList`, `ImmutableValueSet` e `ImmutableValueMap` copiam o
container de origem, expõem leitura sem implementar interface mutável e usam
equality/hash estruturais. Grafos cíclicos de collections aninhadas são
rejeitados na construção.

## Boundaries JSON

`DartitectJsonCodec<T>` retorna `Result` e `DartitectJsonFailure`; failures
contêm kind tipado e path de keys/índices, nunca o valor rejeitado. Codecs
escalares explícitos e combinadores de collections imutáveis ficam em
`DartitectJsonCodecs`. Codecs gerados rejeitam keys desconhecidas por padrão.
O codec integer usa integralidade matemática para VM e Dart Web concordarem;
o codec double amplia integers somente quando preserva o valor.

A travessia untrusted é o padrão: profundidade máxima 64, 10.000 itens em cada
collection e 100.000 nós totais. Outro boundary deve passar
`DartitectJsonLimits.custom`; desativar limites numéricos exige a escolha
visível `DartitectJsonLimits.trusted`. Validação de forma, números finitos e
ciclos continua ativa em trusted mode.

O gerador compõe automaticamente somente escalares lossless, codecs de
generics e collections imutáveis. Datas, enums, IDs, records, narrowing e
outras conversões semânticas exigem um par decoder/encoder estático pertencente
ao consumidor e nomeado por `DartitectField`.
