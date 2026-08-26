# Dartitect

[English](README.md)

Dartitect é uma plataforma native-first de arquitetura e estado owned para Dart
e Flutter. Ele oferece injeção explícita de dependências, ownership de estado,
falhas tipadas, contratos pequenos de observabilidade, verificações de
arquitetura, tooling seguro e adapters opcionais de infraestrutura sem container
global.

Todos os dezesseis pacotes públicos compartilham a linha candidata
`1.0.0-rc.1`. Este cohort está disponível pela tag Git protegida; a publicação
no pub.dev não está autorizada. A readiness formal continua bloqueada por
evidência nativa física e pela decisão separada da autoridade de revisão.

## Por que existe

Codebases Flutter grandes costumam acumular estado global invisível, ownership
ambíguo, imports de infraestrutura em UI/domínio, telemetria presa ao fornecedor
e migrações sem preview seguro. Dartitect torna esses limites explícitos e
preserva os primitivos de Dart e Flutter.

Use-o para injeção por construtor, descarte determinístico, limites feature-first,
falhas esperadas tipadas, listenables nativos, estado reativo owned, telemetria
privacy-first ou adoção verificável. Dentro de uma aplicação Dartitect ele pode
substituir frameworks externos de DI e gerenciamento de estado por capacidade,
sem copiar suas APIs ou seus modelos de lookup global. Ele não é ORM, cliente
HTTP, router, backend, gerador de modelos ou promessa de suporte a todo
fornecedor.

## Princípios

- **Native-first:** prefira tipos Dart, listenables Flutter, construtores e
  composição explícita a um container em runtime.
- **Ownership:** todo recurso é owned ou borrowed; dependentes são descartados
  antes das dependências.
- **Composition roots:** cada app, sessão e isolate de background cria um grafo
  novo. Transfira configuração e contexto de trace validado, não recursos vivos.
- **MVVM estrito:** composition roots constroem ViewModels; Views os recebem e
  nunca buscam repositories, clients, Stores ou services pelo widget context.
- **Estado owned:** commands, values, computeds, resources, families, collections,
  pages e efeitos one-shot têm owners, bounds e teardown explícitos.
- **Falha esperada versus inesperada:** `Result<T, F>` carrega falhas esperadas;
  exceções inesperadas continuam crashes e podem ser reportadas uma vez.
- **Fornecedores pertencem ao consumidor:** clients, Stores, entidades, schemas,
  credenciais, DSNs e configuração permanecem na aplicação.

## Pacotes

| Pacote | Objetivo | Plataformas | Estabilidade |
| --- | --- | --- | --- |
| [`dartitect`](packages/dartitect/) | Result, lifecycle, ownership de recursos, eventos de arquitetura | Dart, Flutter, web | `1.0.0-rc.1` |
| [`dartitect_sync`](packages/dartitect_sync/) | DAG de sync provider-neutral, checkpoints, leases, progresso, protocolo headless | Dart, Flutter, web | `1.0.0-rc.1` |
| [`dartitect_isolates`](packages/dartitect_isolates/) | Workers de isolate tipados/versionados, ACKs, heartbeat, deadlines e safe-stop | Dart VM, Flutter nativo | `1.0.0-rc.1` |
| [`dartitect_flutter`](packages/dartitect_flutter/) | Ownership de ViewModel, comandos async, selectors, scope, binding de erros | Flutter | `1.0.0-rc.1` |
| [`dartitect_observability`](packages/dartitect_observability/) | Logs, redaction, reporting, trace W3C, runtime limitado | Dart, Flutter, web | `1.0.0-rc.1` |
| [`dartitect_dio`](packages/dartitect_dio/) | Ownership de Dio, falhas tipadas, cancelamento, telemetria mínima | Plataformas Dio | `1.0.0-rc.1` |
| [`dartitect_objectbox`](packages/dartitect_objectbox/) | Ownership de Store/query/watcher sobre modelos gerados pelo consumidor | Android, iOS, Linux, macOS, Windows | `1.0.0-rc.1` |
| [`dartitect_sentry`](packages/dartitect_sentry/) | Adapters para Hub Sentry borrowed e inicializado pelo consumidor | Dart, Flutter | `1.0.0-rc.1` |
| [`dartitect_privacy`](packages/dartitect_privacy/) | Status/request ATT explícito, sem prompt automático | iOS; not-supported tipado nas demais | `1.0.0-rc.1` |
| [`dartitect_media`](packages/dartitect_media/) | Permissão de galeria e salvamento de imagem tipados | Android, iOS | `1.0.0-rc.1` |
| [`dartitect_locale_br`](packages/dartitect_locale_br/) | Values imutáveis de CEP brasileiro | Dart, Flutter, web | `1.0.0-rc.1` |
| [`dartitect_geometry`](packages/dartitect_geometry/) | Geometria determinística de polo de inacessibilidade | Dart, Flutter, web | `1.0.0-rc.1` |
| [`dartitect_testing`](packages/dartitect_testing/) | Clocks, probes, telemetria gravada e contract harnesses determinísticos | Dart, Flutter, web | `1.0.0-rc.1` |
| [`dartitect_cli`](packages/dartitect_cli/) | Inspect, scan, doctor, config, baseline, geradores, sync Codex | Dart VM | `1.0.0-rc.1` |
| [`dartitect_lints`](packages/dartitect_lints/) | Diagnósticos de arquitetura via plugin oficial do analyzer | Dart analyzer | `1.0.0-rc.1` |
| [`dartitect_mcp`](packages/dartitect_mcp/) | Tools/resources MCP locais para trabalho revisado | Dart VM, STDIO | `1.0.0-rc.1` |

## Seleção do ecossistema

Escolha o menor conjunto de pacotes e entrypoints para a feature. O
[guia de seleção do ecossistema](docs/guides/ecosystem-selection.pt-BR.md)
mapeia capacidades, plataformas, skills, combinações e contraindicações. As
[receitas de implementação](docs/guides/implementation-recipes.pt-BR.md) cobrem
feature simples, runtime reativo, paginação local-first, mutation/outbox,
observabilidade e composição de adapters com APIs já testadas.
Veja também [geração de modelos](docs/guides/model-generation.pt-BR.md) e a
[política offline do ecossistema](docs/guides/ecosystem-policy.pt-BR.md).

## Início rápido

Até o cohort ser autorizado para o pub.dev, declare o pacote escolhido na versão
candidata e sobrescreva seu fechamento Dartitect completo para a tag Git
protegida. Para `dartitect_flutter`:

```yaml
dependencies:
  dartitect_flutter: 1.0.0-rc.1

dependency_overrides:
  dartitect:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      ref: v1.0.0-rc.1
      path: packages/dartitect
  dartitect_flutter:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      ref: v1.0.0-rc.1
      path: packages/dartitect_flutter
```

Gere os overrides exatos para qualquer combinação dos dezesseis pacotes com
`dart run tool/git_dependency_overrides.dart <pacote>[,<pacote>...]`. O
[guia de consumo do candidato Git](docs/guides/git-candidate-consumption.pt-BR.md)
documenta a validação e a diferença para o futuro canal formal assinado.

```dart
import 'package:dartitect/dartitect.dart';

Future<Result<String, String>> loadName() async => const Ok('Dartitect');

Future<void> main() async {
  final resources = ResourceOwner(label: 'application');
  final result = await loadName();
  switch (result) {
    case Ok(:final value):
      print(value);
    case Err(:final failure):
      print('Esperada: $failure');
  }
  await resources.disposeAsync();
}
```

Comece em [`docs/guides/getting-started.pt-BR.md`](docs/guides/getting-started.pt-BR.md),
selecione o ecossistema e então leia o guia focado do limite alterado.

## Sync e trabalho headless

Adicione `dartitect_sync` quando vários datasets com autoridade local precisarem
de ordenação explícita, checkpoints, leases, progresso, deadlines ou entrega em
background. O pacote fornece apenas mecanismo: repositories continuam donos de
transações locais, mapeamento remoto, idempotência, retry, conflitos,
autenticação e agendamento. Cada request headless cria um grafo owned novo e
transfere dados validados, nunca recursos vivos de provider.

## Observabilidade e adapters

`dartitect_observability` é local-first: logging de desenvolvimento é o padrão;
reporting remoto e tracing são opt-in. Sanitize antes de cada destino. Nunca
registre bodies, headers, queries, credenciais, DSNs, identidade ou paths
identificadores.

Adapters oficiais são pequenos. Dio registra método/protocolo/status, ObjectBox
usa o modelo gerado do consumidor e Sentry recebe um Hub injetado. Para outro
banco, cliente HTTP ou fornecedor, implemente os contratos públicos do
[guia de integrações customizadas](docs/guides/custom-integrations.pt-BR.md).

## CLI e plugin do analyzer

```console
dart run dartitect_cli:dartitect inspect --json
dart run dartitect_cli:dartitect scan --no-baseline
dart run dartitect_cli:dartitect doctor
dart run dartitect_cli:dartitect init --dry-run
dart run dartitect_cli:dartitect baseline create --dry-run
dart run dartitect_cli:dartitect codex sync --dry-run
```

Instale o plugin no pacote consumidor:

```yaml
dev_dependencies:
  dartitect_lints: 1.0.0-rc.1
```

```yaml
# analysis_options.yaml
plugins:
  dartitect_lints:
```

Contribuidores do repositório podem usar o pacote local:

```yaml
plugins:
  dartitect_lints:
    path: packages/dartitect_lints
```

O plugin reporta `DT1001`–`DT1007` como warnings. Suprima uma ocorrência somente
com justificativa: `// dartitect-ignore: DT1004 -- API legada de callback`.
Use `dartitect scan` em CI ou quando o editor não hospedar plugins.

## Skills do Codex

`dartitect codex sync --dry-run` mostra preview de dez skills gerenciadas;
sem `--dry-run`, atualiza somente diretórios `dartitect-*` com manifest e preserva
um `AGENTS.md` existente. A suíte cobre design, adoção, runtime core, runtime
reativo, offline-first, observabilidade, adapters, testing, tooling e MCP local.
Todas permitem invocação implícita e fornecem prompt `$dartitect-*` focado.
Skills do consumidor—incluindo `repository-contribution` deste repositório—nunca
são gerenciadas pelo sync. Skills codificam invariantes; não concedem escrita.

## Servidor MCP local

`dartitect_mcp` é experimental, local, somente STDIO e read-only por padrão.
Expõe tools limitadas de inspeção/preview e resources gerados. Não expõe `create`,
shell, leitura arbitrária, servidor HTTP, OAuth ou acesso remoto a aplicações.

```yaml
dev_dependencies:
  dartitect_mcp: 1.0.0-rc.1
```

```console
dart run dartitect_mcp:dartitect_mcp --root .
codex mcp add dartitect -- dart run dartitect_mcp:dartitect_mcp --root .
```

Configuração Codex no projeto:

```toml
[mcp_servers.dartitect]
command = "dart"
args = ["run", "dartitect_mcp:dartitect_mcp", "--root", "."]
default_tools_approval_mode = "writes"
startup_timeout_sec = 20
tool_timeout_sec = 120
```

Para permitir mudanças revisadas, acrescente `--allow-writes`. Ainda são
obrigatórios preview, `planId` opaco/não expirado/single-use, `confirmed = true`,
aprovação do cliente, revalidação integral, serialização e lock. Consulte o
[guia MCP](docs/guides/mcp.pt-BR.md).

## Compatibilidade e versionamento

O workspace exige Dart `^3.13.0`; pacotes Flutter exigem Flutter `>=3.47.1`.
ObjectBox não suporta web. CLI/MCP são ferramentas locais de VM. Pacotes
candidatos podem receber correções de API antes de um novo release; o cohort
completo de dezesseis pacotes evolui em lockstep.

Somente a config v1 estável é aceita; versões experimentais não possuem
migração. Baselines ignoram números de linha. Mudanças de API pública são
comparadas com snapshot revisado.

## Limitações e segurança

Dartitect não valida lógica de negócio, não torna SDKs de fornecedor seguros,
não oculta limites de isolates e não garante rollback contra processos hostis.
Arquivos generated-once passam a pertencer ao consumidor; apenas artefatos
fully-generated com manifest podem ser substituídos.

Não coloque credenciais em `dartitect.json`, MCP, exemplos, issues ou logs.
Reporte vulnerabilidades por GitHub Security Advisories; veja
[`SECURITY.pt-BR.md`](SECURITY.pt-BR.md).

## Contribuição

Leia [`CONTRIBUTING.pt-BR.md`](CONTRIBUTING.pt-BR.md) e o
[Código de Conduta](CODE_OF_CONDUCT.pt-BR.md). Novos adapters precisam de pacote
isolado, testes reais, docs públicas, rationale de dependência, revisão de
licença e atualização das skills. Toda mudança normal segue o fluxo de branch
curta, PR completo, checks obrigatórios e squash do
[guia de contribuição](docs/guides/repository-contribution.pt-BR.md). Os comandos
de verificação não publicam.

## Licença e próximos passos

A linha candidata atual e as versões futuras usam a
[Licença BSD 3-Clause](LICENSE). As prioridades restantes são CI de plataformas
e Security/advisories no SHA final, evidência nativa física e uma decisão
explícita de readiness pela autoridade de revisão delegada.
