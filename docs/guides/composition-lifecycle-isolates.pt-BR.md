# Composição, lifecycle e isolates

[English](composition-lifecycle-isolates.md)

## Composition roots

Monte grafos explícitos de aplicação, sessão, feature, rota, operação e isolate
receptor. Crie apenas os escopos necessários, mas nunca deixe um escopo filho
viver mais que o pai. Prefira injeção por construtor. Não crie runtimes, Stores,
Dio, Hubs ou service locators globais, nem objetos vivos entre isolates.

## Matriz de contrato de lifecycle 1.0

A matriz a seguir é normativa para 1.0. `E`, `T` e `P` significam durabilidade
efêmera, temporária e persistida, definidas abaixo.

| Lifetime | Raiz e evento terminal | Limite owned | Limite borrowed | Transferência e durabilidade | Teardown obrigatório |
| --- | --- | --- | --- | --- | --- |
| Aplicação | Composição do processo/app; encerramento do app | Clients, Stores, executors e observabilidade owned do processo | Serviços de host/plataforma com owner externo | Commit da transação; `E/T/P` | Todos os escopos filhos, depois dependentes da aplicação antes das dependências; flush/dispose de observabilidade por último |
| Sessão | Geração de autenticação, conta ou tenant; logout, troca ou fim do pai | Credenciais, clients, repositories e caches da sessão | Serviços da aplicação | Commit da transação; `E/T/P` | Operações, rotas e features; depois dependentes da sessão antes das dependências |
| Feature | Estado deliberadamente compartilhado por várias rotas; desativação da feature ou fim do pai | Comandos, recursos, watchers e caches da feature | Serviços da sessão/aplicação | Commit da transação; `E/T/P` | Operações e rotas; depois dependentes da feature antes das dependências |
| Rota | Composição de uma rota ou ViewModel; unmount/remoção ou fim do pai | ViewModels, bindings, observations e recursos locais da rota | Serviços da feature/sessão | Commit da transação; `E/T`; escritas persistidas usam Store de vida mais longa | Operações primeiro; depois bindings/observations antes de suas fontes |
| Operação | Uma tentativa admitida de comando/leitura/recurso; sucesso, falha, cancelamento cooperativo, deadline ou fim do pai | Cancelamento, timers, subscriptions, queries e artefatos temporários da tentativa | Rota/feature/serviço usado pela tentativa | Commit da transação; `E/T`; resultados persistidos usam Store de vida mais longa | Fechar admissão, drenar a tentativa admitida e liberar os recursos da tentativa |
| Isolate | Um entrypoint receptor e seu grafo local; parada graciosa, cleanup de crash ou fim do processo | Ports, workers, wrappers de Store anexados, queries e grafo locais ao receptor | Nenhum objeto vivo borrowed cruza a fronteira | Somente mensagens serializáveis; `E/T/P` permanecem locais ao receptor | Parar admissão, drenar ou atingir o fallback de deadline, executar `finally` local e fechar ports/grafo |

## Regras de ownership e transferência

- **Owned:** o escopo que adquire registra o valor somente após aquisição com
  sucesso, libera exatamente uma vez e impede uso depois do início do teardown.
- **Borrowed:** o borrower nunca registra nem fecha o valor. O provider precisa
  viver mais que todos os borrowers.
- **Transferred:** `ResourceTransaction.commit()` move atomicamente todo o
  conjunto owned para um `OwnedGraph` e torna a transação terminal.
  `OwnedRuntimeSlot.replaceGraph()` pode então assumir ownership desse grafo
  completo. Valores borrowed não se movem. Dartitect não oferece transferência
  individual de recurso vivo entre owners, gerações ou isolates.

`OwnedRuntimeSlot.replace()` monta uma nova transação antes da publicação. Em
uma troca bem-sucedida, fecha a admissão antiga, publica o novo grafo commitado,
drena o trabalho antigo e então encerra o grafo anterior. Falha de construção
mantém válida a geração anterior.

## Durabilidade

- **Efêmera (`E`)** existe apenas no grafo vivo. O teardown fecha ou descarta;
  exemplos incluem timers, controllers, subscriptions, queries e leases.
- **Temporária (`T`)** pode usar disco ou storage de plataforma, mas é
  substituível. O owner criador registra o fechamento do handle e a remoção; a
  recuperação inicial remove resíduos de crash antes do reuso.
- **Persistida (`P`)** sobrevive ao teardown do grafo e a restart. O grafo ainda
  possui e fecha handles vivos de Store/arquivo/query; somente uma operação
  explícita de retenção ou exclusão de domínio pode remover os dados.

Durabilidade descreve dados, não ownership de handles. Um wrapper de Store
persistido ainda é efêmero para o grafo que o possui.

## Teardown e falha

Adquira providers antes de dependentes e registre imediatamente cada valor
owned, para `ResourceOwner` liberar dependentes antes das dependências em ordem
reversa. Todo escopo segue a mesma sequência terminal:

1. Rejeitar trabalho novo e sinalizar cancelamento cooperativo quando aplicável.
2. Drenar trabalho já admitido; somente a fronteira de isolate/processo pode
   ter fallback forçado por deadline documentado.
3. Liberar escopos filhos e recursos owned em ordem reversa de registro.
4. Ignorar valores borrowed, continuar depois de cada falha de cleanup e
   reportar todas juntas em `ResourceCleanupException`.
5. Limpar registros, tornar-se terminal, rejeitar uso futuro e compartilhar a
   mesma conclusão entre chamadas concorrentes ou repetidas de disposal.

Falha de construção faz rollback apenas das aquisições concluídas. Falha no
rollback é preservada separadamente do erro original de construção.

## Isolates

Transfira configuração imutável, mensagens e contexto W3C validado. Para
ObjectBox, envie bytes de referência, anexe outro Store e feche em `finally`.

Projection permanece `ProjectionExecution.inline` a menos que a composição
injete explicitamente um `ProjectionExecutor`. `IsolateProjectionExecutor` cria
um worker por task e aceita somente callback/request/result transferíveis. Uma
geração cancelada ou superseded não publica, mas o worker pode concluir seu
`finally` local ao isolate; descarte o executor para drenar todos os exits.

No ObjectBox, `ObjectBoxProjectionExecutor` toma o Store original borrowed e usa
`Store.runAsync`, cujo callback recebe outro Store wrapper anexado. Crie e feche
cada query e graph background dentro desse callback. Descarte collection,
executor e Store original nessa ordem. Nunca envie Store, query, owner, client
ou closure que capture um deles pela fronteira.

## Checklist de revisão

- O composition root está visível e testável.
- Cada valor está classificado como owned, borrowed ou transferido por transação.
- Dados estão classificados como efêmeros, temporários ou persistidos.
- Providers são registrados antes dos dependentes, produzindo teardown reverso.
- Cada entrypoint background cria e encerra seu grafo.
- Projection background é explícita, protegida por geração e totalmente drenada.
- Exceções inesperadas são relançadas após reporting opcional.
