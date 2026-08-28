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

## Projections e lenses

`@DartitectProjection(name: ..., fields: ...)` gera typedef de record nomeado,
selector puro e descriptors/lenses de campos tipados. Uma lista `fields` vazia
seleciona todos os campos do primary constructor; caso contrário, a ordem é a
ordem explícita da lista. A lens reconstrói o modelo imutável e nunca expõe
mutação ou reflexão. Projection não habilita value equality, JSON ou mappers.

## Mappers de boundary

`@DartitectMapper(Target)` gera mapper puro que retorna
`Result<Target, DartitectMappingFailure>`. Use `bidirectional: true` somente
quando cada campo reverso for independentemente lossless.
`DartitectField(targetName: ...)` é a única metadata de rename automático.
Hooks estáticos exatos e consumer-owned em `mapToWith`/`mapFromWith` tornam a
conversão semântica visível e preservam path sem payload dos campos declarados
nas falhas esperadas.

Mapping automático se restringe a escalares semanticamente assignable/lossless
e collections imutáveis Dartitect. Narrowing, enum/string, datas, IDs,
relations, flattening e schemas de providers nunca são inferidos. Targets e
hooks continuam consumer-owned.
