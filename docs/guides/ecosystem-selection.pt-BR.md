# Seleção do ecossistema Dartitect

[English](ecosystem-selection.md)

## Comece pelo limite

Selecione pacotes pelo comportamento realmente necessário. `dartitect` é o core
para falhas tipadas, concorrência, ownership e contratos de mutation offline.
Todos os outros pacotes são opcionais. SDKs de provider, entidades/schemas,
credenciais e configuração de fornecedor pertencem ao consumidor; boilerplate
opt-in de modelos imutáveis pode ser gerado em parts commitados do consumidor.

Para aplicação ou feature nova, use `$dartitect-design`. Uma codebase existente
pode usar `$dartitect-audit` para evidência read-only de conformidade. Isso não é
um caminho para migrar ou coexistir com outro runtime de DI/application state.

## Matriz de capacidades

| Capacidade | Pacote(s) | Entrypoint(s) público(s) | Plataformas | Skill focada | Não escolha quando |
| --- | --- | --- | --- | --- | --- |
| Results, ownership, command lanes, contratos de mutation | `dartitect` | `package:dartitect/dartitect.dart` | Dart, Flutter, web | `$dartitect-runtime`; `$dartitect-offline-first` para mutations | Espera-se service locator, state manager, logger, ORM ou cliente HTTP |
| Values imutáveis, codecs JSON, projections/lenses, mappers de boundary | `dartitect_modeling` | `package:dartitect_modeling/dartitect_modeling.dart` | Dart, Flutter, web | `$dartitect-modeling` | Esperam-se entities mutáveis/de provider, conversões inferidas ou reflexão runtime |
| Compiler/IR semântico compartilhado de modelagem | `dartitect_modeling_analyzer` | `package:dartitect_modeling_analyzer/dartitect_modeling_analyzer.dart` | Tooling Dart VM | `$dartitect-modeling`; `$dartitect-tooling` | Algum runtime da aplicação dependeria de Analyzer, formatter, CLI ou geração |
| Sync de DAG de datasets, checkpoints, leases, progresso, protocolo headless | `dartitect_sync` | `package:dartitect_sync/dartitect_sync.dart` | Dart, Flutter, web | `$dartitect-offline-first`; `$dartitect-testing` | Espera-se scheduler, política de retry, fila durável, cliente de provider ou engine de conflitos |
| ViewModels e commands Flutter básicos | `dartitect_flutter` | `package:dartitect_flutter/dartitect_flutter.dart` | Flutter | `$dartitect-runtime` | São necessários recursos hot/warm/cold avançados ou páginas local-first |
| Grafo reativo, resources, families, collections, builders headless | `dartitect_flutter` | `package:dartitect_flutter/dartitect_flutter_reactive.dart` | Flutter | `$dartitect-reactive` | Composição básica com `ChangeNotifier`/command é suficiente |
| Logs, reporting, tracing, redaction | `dartitect_observability` | `package:dartitect_observability/dartitect_observability.dart` | Dart, Flutter, web | `$dartitect-observability` | Nenhum destino remoto foi escolhido explicitamente; logging local já basta |
| Integração Dio | `dartitect_dio` | `package:dartitect_dio/dartitect_dio.dart` | Plataformas Dio | `$dartitect-adapters` | A aplicação não escolheu Dio ou o import atravessaria domínio/presentation |
| Integração Drift | `dartitect_drift` | `package:dartitect_drift/dartitect_drift.dart` | Dart, Flutter, web | `$dartitect-adapters`; combine com `$dartitect-offline-first` | O consumidor espera schema/executor pertencente ao SDK ou abstração universal de banco |
| Integração ObjectBox | `dartitect_objectbox` | `package:dartitect_objectbox/dartitect_objectbox.dart` | Android, iOS, Linux, macOS, Windows | `$dartitect-adapters`; combine com `$dartitect-offline-first` | É necessário web ou abstração ORM |
| Integração Sentry | `dartitect_sentry` | `package:dartitect_sentry/dartitect_sentry.dart` | Dart, Flutter | `$dartitect-adapters` + `$dartitect-observability` | O consumidor não inicializou/escolheu Sentry ou outro hook já captura a mesma telemetria |
| Autorização de tracking | `dartitect_privacy` | `package:dartitect_privacy/dartitect_privacy.dart` | iOS; not-supported tipado nas demais | `$dartitect-adapters` | A autorização seria solicitada automaticamente ou ATT não é necessário |
| Salvamento de imagem na galeria | `dartitect_media` | `package:dartitect_media/dartitect_media.dart` | Android, iOS | `$dartitect-adapters` | Espera-se picker/editor, pipeline de vídeo ou abstração ampla de mídia |
| Value de CEP brasileiro | `dartitect_locale_br` | `package:dartitect_locale_br/dartitect_locale_br.dart` | Dart, Flutter, web | `$dartitect-runtime` | Esperam-se widgets gerais de formulário ou outros documentos brasileiros |
| Polo de inacessibilidade de polígono | `dartitect_geometry` | `package:dartitect_geometry/dartitect_geometry.dart` | Dart, Flutter, web | `$dartitect-runtime` | Espera-se engine GIS ou modelo geométrico mutável |
| Helpers determinísticos de limites | `dartitect_testing` | `package:dartitect_testing/dartitect_testing.dart` | Dart, Flutter, web | `$dartitect-testing` | O teste precisa provar o limite real do provider/codegen |
| Inspect, scan, doctor, config, baselines, geradores, sync Codex | `dartitect_cli` | `package:dartitect_cli/dartitect_cli.dart`; executável `dartitect` | Dart VM | `$dartitect-tooling` | Espera-se comportamento de runtime ou serviço remoto |
| Diagnósticos do analyzer | `dartitect_lints` | plugin `package:dartitect_lints/main.dart` | Dart analyzer | `$dartitect-tooling` | O host não roda plugins do analyzer; use `dartitect scan` |
| Tools/resources MCP locais | `dartitect_mcp` | `package:dartitect_mcp/dartitect_mcp.dart`; executável STDIO local | Dart VM, STDIO | `$dartitect-mcp` | São necessários shell/CI, arquivos arbitrários, HTTP/OAuth ou acesso à aplicação em execução |

O instalador do fixture ObjectBox nativo, `tool/setup_objectbox_vm.dart`, pertence
a `$dartitect-tooling`; não é entrypoint da aplicação.

## Cenários de roteamento

| Cenário | Comece com | Combine quando necessário |
| --- | --- | --- |
| Aplicação ou feature nova | `$dartitect-design` | Encaminhe o limite selecionado para uma ou mais skills focadas |
| Auditoria de conformidade de codebase existente | `$dartitect-audit` | Evidência read-only; nenhum plano de conversão é emitido |
| Values imutáveis gerados | `$dartitect-modeling` | `$dartitect-tooling` para integração de CI/release |
| Runtime Flutter simples | `$dartitect-runtime` | `$dartitect-testing` |
| Lifecycle e UI reativos | `$dartitect-reactive` | `$dartitect-runtime`, `$dartitect-testing` |
| Paginação local-first ou outbox durável | `$dartitect-offline-first` | `$dartitect-reactive`, provider via `$dartitect-adapters`, `$dartitect-testing` |
| Sync foreground ou headless de datasets | `$dartitect-offline-first` | `$dartitect-adapters`, `$dartitect-observability`, `$dartitect-testing` |
| Dio, Drift, ObjectBox, Sentry ou provider customizado | `$dartitect-adapters` | `$dartitect-observability` ou `$dartitect-offline-first` conforme a política |
| Política e captura de telemetria | `$dartitect-observability` | `$dartitect-adapters` somente após escolher o provider |
| Verificação de falha/lifecycle/provider | `$dartitect-testing` | A skill focada da implementação |
| CLI, scanner, lints, geradores, setup nativo, gates | `$dartitect-tooling` | Mantenha MCP separado |
| Inspeção local por agente e previews revisados | `$dartitect-mcp` | Use CLI diretamente em scripts e CI |

Fluxos transversais invocam intencionalmente mais de uma skill. A sobreposição
não transfere ownership: cada skill responde apenas por seu limite nomeado.

## Stacks recomendados

- Serviço Dart puro: `dartitect`; adicione `dartitect_observability` somente para
  um contrato concreto e `dartitect_testing` como dependência de desenvolvimento.
- Boundary modelado imutável: adicione `dartitect_modeling` no runtime e mantenha
  `dartitect_cli`/`dartitect_modeling_analyzer` apenas no tooling de
  desenvolvimento; escolha value, JSON, projection e mapper independentemente.
- Feature Flutter básica: `dartitect` + `dartitect_flutter` pelo entrypoint fino;
  o entrypoint reactive não é necessário.
- Feature Flutter reativa: adicione somente o entrypoint reativo e mantenha a
  renderização Material ou Cupertino na presentation consumidora.
- Feature offline-first: contratos de mutation do core + presentation reativa de
  autoridade local + `dartitect_sync` quando houver orquestração de datasets +
  adapters de storage/transporte escolhidos. O repository possui transação,
  schema, conflito, retry, agendamento e compensação.
- Enforcement de arquitetura: `dartitect_cli` em scripts/CI e
  `dartitect_lints` nos hosts de editor/analyzer suportados.
- Trabalho local assistido por agente: adicione `dartitect_mcp` como dev
  dependency. Mantenha read-only, salvo escrita local revisada e intencional.

## Checks de ownership e plataforma

Crie um grafo por app, sessão, rota ou isolate de background. Descarte bindings/
commands, observações reativas e watchers/queries de provider, clients e Stores,
depois observabilidade owned. SDKs do consumidor fecham após todos os borrowers
Dartitect.

Antes de assumir um stack, verifique web versus nativo, entrypoints Flutter
versus Dart puro, dependência Material, hosts ObjectBox, Dart VM para CLI/MCP,
licença do provider e o fixture real de codegen/SDK necessário aos testes.

## Próximo passo

Use as [receitas de implementação](implementation-recipes.pt-BR.md) para uma
composição concreta. O [guia de primeiros passos](getting-started.pt-BR.md)
cobre instalação; os guias focados cobrem composição, runtime reativo,
observabilidade, adapters e MCP em profundidade.
