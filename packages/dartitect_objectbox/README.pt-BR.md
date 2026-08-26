# dartitect_objectbox

[English](README.md)

## Objetivo

Ownership e lifecycle de observação opcionais sobre um `Store` ObjectBox real.
Entidades, model JSON e código gerado pertencem ao consumidor.

## Quando usar

Use no composition root nativo após escolher ObjectBox e gerar seu modelo. Não
é abstração ORM e não suporta web.

## Quando não usar

Não use em web, antes de o consumidor possuir um modelo ObjectBox gerado ou para
esconder entidades/schema atrás de abstração ORM genérica. Nunca transfira Store
vivo entre isolates.

## Combinações recomendadas

Combine com o entrypoint reativo para autoridade local baseada em watchers e
com contratos de mutation do core para outbox transacional. Mantenha adapters de
transporte e telemetria separados. Consulte o
[guia de seleção do ecossistema](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.pt-BR.md)
e as [receitas de implementação](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.pt-BR.md).

## Instalação

Este candidato não está publicado no pub.dev. Declare
`dartitect_objectbox: 1.0.0-rc.1` e use o
[guia de consumo do candidato Git](../../docs/guides/git-candidate-consumption.pt-BR.md)
para gerar o fechamento completo de overrides.

## Exemplo mínimo

```dart
final owner = await ObjectBoxStoreOwner.create(openStore: openStore);
try {
  final store = owner.store;
  // Use boxes criados com suas entidades/modelo gerados.
} finally {
  await owner.disposeAsync();
}
```

Para leituras reativas, passe uma factory de builder gerado pelo consumidor a
`ObjectBoxQuerySource<T, F>` e injete-a em `LiveResource<List<T>, F>`. O recurso
toma o Store borrowed, cria uma query watcher por ativação hot e fecha ambos ao
se tornar warm ou cold.

`example/` inclui modelo realmente gerado e executável publicáveis. A fixture do
repositório acrescenta cobertura de Store/query/watcher, lock, limpeza e
referência para isolate.

## Tour da API pública

- `ObjectBoxStoreOwner.create`, `.value` e `.temporary` explicitam ownership.
- `ObjectBoxObservationOwner` drena queries/watchers antes do Store.
- `ObjectBoxInstrumentation` envolve open/close com tracing mínimo.
- `objectBoxStoreReference` cria bytes transferíveis entre isolates.
- `ObjectBoxQuerySource` converte invalidations do watcher em leituras
  `LiveResource` limitadas sem possuir Store ou entidades do consumidor.
- `ObjectBoxVersionedProjection` aplica extractors de ID/version definidos pelo
  consumidor a uma `LiveCollection`, reprojetando somente entidades novas ou
  alteradas.
- `ObjectBoxProjectionExecutor<P, R>` toma o Store original borrowed e delega
  trabalho background explícito a `Store.runAsync`. O callback recebe um Store
  local ao isolate; feche graphs e queries criados nele em `finally` e descarte
  o executor antes do Store original.
- `ObjectBoxMutationTransaction` toma um Store borrowed e executa callback de
  escrita síncrono. Coloque nele as escritas das entities de domínio e outbox do
  consumidor; `Ok` confirma ambas, enquanto `Err` tipado ou exceção reverte as
  duas.

## Ownership

O consumidor possui entidades, schemas, gerados, migrations, chaves e config.
Feche streams/watchers/queries antes do Store. Outro isolate anexa seu próprio
Store e o fecha em `finally`.

## Limitações

Web não é suportada. Lock do mesmo path e compatibilidade de modelo continuam
responsabilidade do ObjectBox. Callbacks transacionais devem ser síncronos. O
helper não define entities, schema de outbox, política de conflito ou transport.
Cancelamento background descarta publicação, mas não interrompe uma operação
nativa em andamento. Somente requests/results transferíveis são válidos. Nunca
edite gerados manualmente.

## Extensão

Mantenha contratos no domínio e implementações ObjectBox em data. Propostas
reutilizáveis precisam de fixture real gerada.

## Testes

Execute `flutter test` e `tool/objectbox_native_fixture`. A fixture valida
`Query.findAsync`, projection background, cleanup de Store local ao isolate,
commit/rollback reais de domínio/outbox e teardown de watcher; não substitua
essa cobertura somente por mocks.

## Links

Veja [adapters](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/adapters.pt-BR.md),
[integrações customizadas](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/custom-integrations.pt-BR.md) e o [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
