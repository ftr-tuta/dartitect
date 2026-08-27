# Matriz Flutter para Dartitect Native Strict

[English](native-strict-matrix.md)

Dartitect 1.0 suporta aplicações greenfield Native Strict. Projetos existentes
podem usar a auditoria read-only de conformidade; não há workflow suportado de
migração ou coexistência de runtime.

| Responsabilidade Flutter/aplicação | Contrato Native Strict | Superfície Dartitect principal | Limite sob ownership do consumidor |
| --- | --- | --- | --- |
| View | Recebe ViewModel ou input imutável de apresentação; nunca localiza repositories, clients, Stores ou services de aplicação pelo `BuildContext` | `ViewModelHost`, builders, `EffectListener` | Árvore de widgets, apresentação Material/Cupertino, routing |
| ViewModel | Construído em root explícita de app/sessão/feature/rota; possui apenas seu lifetime declarado | `dartitect_flutter`, `ResourceOwner`, `OwnedGraph` | Política da feature e ports de aplicação injetados |
| Escritas | Escritas relevantes são métodos, Commands ou transactions explícitas; getters, selectors, computeds e `build` não produzem effects | `Command0`/`Command1`, command lanes, transactions reativas | Política de mutation do domínio e implementação da transaction do provider |
| Falha esperada | Sucesso/falha tipados e exaustivos; exceptions inesperadas continuam crashes com stack original | `Result<T, F>` | Tipos de falha de domínio/aplicação e renderização para o usuário |
| Injeção de dependência | Constructor injection a partir de composition roots visíveis; sem service locator nem lookup por contexto | Grafos owned e construtores explícitos | Repository/client/provider concreto selecionado |
| Repository | Port de aplicação/domínio aponta para dentro; tipos do SDK ficam em infrastructure | Adapters opcionais Dio/ObjectBox somente na composição | Entidades, schema, operações de banco/HTTP, serialização, idempotência, conflito e retry |
| Fluxo unidirecional | Estado autoritativo publica para baixo; intent passa por método/Command; leituras nunca escrevem | Values, computeds, resources, collections, Commands | Shape do estado e mapeamento de evento para intent da feature |
| Lifetime de sessão | Uma generation possui os recursos; logout/switch remove rotas, fecha admissão, drena e então descarta | `OwnedRuntimeSlot`, `SessionStateController` | Autenticação, credenciais, política de tenant/account |
| Effects one-shot | Entrega local tipada, bounded e no máximo uma vez; contexto só existe no consumidor Flutter mounted | `EffectChannel`, `EffectListener` | Navegação, dialogs, snack bars e política de rota ativa |
| Estado local-first | A publicação do repository local é autoridade de presentation; trabalho remoto escreve pelo repository e aguarda observação causal | `LiveResource`, `PagedLiveResource`, contratos de mutation/outbox e orquestração de sync | Transaction do Store, outbox durável, codec de checkpoint, scheduling, suporte a fencing e protocolo distribuído |

Runtimes concorrentes de DI ou application state—including Riverpod, BLoC,
Provider, GetIt, MobX e Signals—são incompatíveis com o perfil Native Strict
porque introduzem uma segunda autoridade de composição/lifecycle de estado. É
um contrato de escopo, não julgamento de qualidade desses packages fora do
Dartitect.

Use `dartitect scan --no-baseline` como gate canônico de conformidade para um
projeto novo. Baselines apenas descrevem dívida legada revisada e nunca
enfraquecem esse gate greenfield.
