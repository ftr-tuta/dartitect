# Fluxo de contribuição do repositório

[English](repository-contribution.md)

## Escopo e invariantes

Toda mudança versionada normal chega à `main` por pull request. Não envie
trabalho normal diretamente para a `main`, não contorne seu ruleset, não
enfraqueça checks obrigatórios e não use procedimento emergencial por
conveniência. Preserve mudanças locais não relacionadas.

Commits do repositório têm a única identidade canônica `ftr <ftr@tuta.com>` e
usam Conventional Commits. A configuração local `user.useConfigOnly=true`
impede que uma identidade global ambiente seja usada por engano.

## Inicie uma branch curta

Comece pela mainline remota atual:

```console
git fetch --prune origin
git switch -c <tipo>/<propósito-curto> origin/main
git config --local user.name ftr
git config --local user.email ftr@tuta.com
git config --local user.useConfigOnly true
```

Use apenas `feat/`, `fix/`, `ci/`, `docs/`, `chore/` ou `release/`. Mantenha
nome, escopo e duração curtos. Verifique a árvore de trabalho e o `AGENTS.md`
aplicável antes de editar.

## Implemente e verifique

Mantenha commits revisáveis de forma independente e escreva títulos de
Conventional Commits. Escolha checks proporcionais ao limite afetado:

- mudanças somente de documentação executam formatação e os checks de docs,
  políticas, links e skills que possam ser afetados;
- código Dart ou Flutter executa formatação, análise e testes focados pelo limite
  público ou real do fornecedor;
- dependências, release, código nativo ou mudanças transversais executam supply
  chain e os gates completos relevantes de `tool/verify.dart` e
  `tool/release_audit.dart`;
- todo comando pedido explicitamente continua obrigatório mesmo se o diff
  parecer de baixo risco.

Adicionar ou alterar plugin Flutter exige regenerar e versionar toda integração
nativa afetada. Execute resolução/build Flutter no host compatível e inspecione
registrants, projetos de build e workspaces gerados. Em especial, versione a
integração CocoaPods emitida para iOS e macOS. Builds de plataforma devem terminar
com `git diff --exit-code -- .` limpo.

Revise o diff completo e `git diff --check` antes de cada commit. Não misture
limpeza não relacionada, HTML Dartdoc gerado, publicação ou tags na mudança.

## Abra e complete o pull request

Envie somente a branch de tópico. Use título Conventional Commit adequado ao
commit final de squash e complete cada seção aplicável do template: resultado,
ownership, compatibilidade, impacto de plataforma, evidências, integração nativa
e gates hospedados restantes.

O GitHub Actions faz checkout e build do merge candidate. Em `pull_request`, o
release audit recebe `github.event.pull_request.head.sha` somente para autoria,
para que o autor do merge sintético do GitHub não esconda nem rejeite autores da
branch. Em `push`, todo o histórico da `main` é auditado. Em `merge_group`,
commits que não são merge são auditados e o merge sintético da fila é excluído.

Se um check falhar, corrija na mesma branch e mantenha o ruleset inalterado.
Resolva conversas de review e atualize a branch quando exigido. Com um único
mantenedor, o ruleset exige intencionalmente zero aprovações, mas ainda exige
`CI / Required` e threads resolvidas.

## Faça squash e limpe

Antes de habilitar auto-merge, confirme que a conta GitHub seleciona
`ftr@tuta.com` para operações web e que a privacidade de e-mail não força autor
`noreply` no squash. Faça merge somente por squash: o título do PR vira o título
do commit e as mensagens dos commits viram o corpo. O GitHub apaga a branch de
tópico automaticamente.

Após o merge, aguarde `CI / Required` na `main`. Confirme que o remoto tem somente
`main`, o ruleset não tem atores de bypass, o novo commit e todo o histórico
alcançável têm autoria canônica e o GitHub lista somente `ftr-tuta` como
contribuidor. Verifique que clone novo está limpo. Crie e verifique novo bundle
final sem remover backups anteriores.

## Recuperação break-glass

Atualizar a `main` diretamente é recuperação excepcional com autoridade mais
restrita que trabalho normal. Exige autorização explícita que nomeie recuperação,
ref alvo, SHA remoto esperado e substituição pretendida. Antes de qualquer
mutação:

1. atualize e registre refs remotos exatos, configurações do repositório e
   ruleset completo;
2. crie `git bundle create <backup>.bundle --all` com timestamp, execute
   `git bundle verify <backup>.bundle` e preserve backups anteriores;
3. prepare e teste rollback que restaure o SHA capturado da `main`;
4. se uma proteção precisar mudar, prepare restauração automática antes da
   alteração e faça a menor mudança temporária possível.

Nunca use `git push --mirror`. Atualize somente `refs/heads/main` e, quando o
histórico precisar ser substituído, use lease exato como:

```console
git push --force-with-lease=refs/heads/main:<sha-remoto-capturado> origin <sha-recuperação>:refs/heads/main
```

Restaure toda proteção imediatamente, inclusive em falha; não deixe ator de
bypass nem regra desabilitada durante diagnóstico. Atualize e verifique refs,
autoria canônica, ruleset, CI, Security, clone novo limpo e novo bundle final
verificado. Se a validação falhar, volte ao SHA capturado com lease exato recém
observado, restaure primeiro as proteções e relate a recuperação com falha.

## Configurações do repositório para mantenedores

Permita somente squash merge. Habilite auto-merge, atualização de branch e
exclusão automática da branch de tópico. Configure o título do squash a partir
do título do PR e o corpo a partir dos commits.

Proteja a `main` sem atores de bypass, com proteção contra exclusão e
non-fast-forward, resolução obrigatória de threads, branch atualizada, zero
aprovações enquanto houver apenas um mantenedor e exatamente um check
obrigatório: `CI / Required`. Seu grafo contém todas as dependências de
plataformas, nativas, segurança, auditoria, benchmarks e canários; não configure
jobs componentes como checks obrigatórios separados.
