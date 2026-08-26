# Contribuindo com Dartitect

[English](CONTRIBUTING.md)

## Antes de abrir uma mudança

Pesquise issues, mantenha escopo pequeno e descreva o limite de
ownership/composição afetado. Para segurança, pare e use o processo privado em
`SECURITY.pt-BR.md`.

## Setup de desenvolvimento

Instale Dart `^3.13.0` e Flutter `>=3.47.1` e execute:

```console
flutter pub get
dart run tool/verify.dart --skip-get
```

Use `dart run tool/setup_objectbox_vm.dart` antes da fixture ObjectBox nativa.
HTML de API em `docs/api/` é somente local.

Commits do repositório devem usar a identidade canônica e proteção somente
local:

```console
git config --local user.name ftr
git config --local user.email ftr@tuta.com
git config --local user.useConfigOnly true
```

Não altere a identidade Git global para trabalhar no Dartitect.

## Branches e commits

Trabalho normal nunca começa nem entra diretamente na `main`. Atualize o remoto
e crie uma branch curta a partir de `origin/main` com `feat/`, `fix/`, `ci/`,
`docs/`, `chore/` ou `release/`. Use Conventional Commits e mantenha todos os
commits com autoria `ftr <ftr@tuta.com>`.

Não contorne as proteções de branch. Preserve trabalho local não relacionado,
mantenha a branch focada e corrija checks com falha na mesma branch.

## Requisitos da mudança

- Preserve injeção por construtor native-first e estado owned/borrowed explícito.
- Teste por entrypoints públicos e limites reais quando necessário.
- Documente toda API suportada e atualize o snapshot.
- Mantenha docs canônicas em inglês e estrutura pt-BR correspondente.
- Atualize ledgers, licenças, SBOM, skills e gates quando afetados.
- Ao adicionar ou alterar plugin Flutter, regenere e versione toda integração
  afetada de projeto/workspace nativo, incluindo CocoaPods em iOS e macOS, e
  prove que os builds de plataforma não alteram a árvore versionada.
- Não publique pacotes, crie tags ou versione Dartdoc HTML.

## Checklist de novo adapter

- [ ] Pacote opcional isolado com config do fornecedor owned pelo consumidor.
- [ ] Teste de limite real e testes determinísticos sem rede quando aplicável.
- [ ] Lifetime owned/borrowed e disposal reverso explícitos.
- [ ] Telemetria mínima/redacted sem credenciais, bodies, headers ou identidade.
- [ ] README English/pt-BR, exemplo, Dartdoc, changelog, licença e topics.
- [ ] Rationale de dependência/versão, licença e advisory revisados.
- [ ] Snapshot, catálogo e cobertura das skills atualizados.

## Pull requests

Explique resultado, testes, plataformas, risco de compatibilidade e validação
externa restante. Complete cada item aplicável do template e execute checks
proporcionais antes do push. Os checks obrigatórios de CI e Security devem passar
contra o merge candidate; o audit de autoria usa o head do PR porque o GitHub cria
um commit de merge sintético.

Use somente squash merge, com o título do PR como título final do Conventional
Commit. Resolva todas as conversas, atualize a branch quando exigido e apague a
branch curta após o merge. Dry-run aprovado não autoriza publicação. Veja o
[fluxo completo de contribuição](docs/guides/repository-contribution.pt-BR.md).

## Recuperação emergencial

Atualizações diretas da `main` são operações break-glass, não um fluxo de
contribuição. Exigem autorização explícita, bundle verificado e backup do estado
remoto, force-with-lease exato quando rewrite for inevitável, rollback testado e
restauração imediata de toda proteção. Nunca use `git push --mirror`. Siga o
procedimento do guia sem enfraquecer checks para trabalho normal.
