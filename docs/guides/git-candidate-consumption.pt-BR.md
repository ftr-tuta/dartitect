# Consumo do candidato Git

[English](git-candidate-consumption.md)

## Canal

`v1.0.0-rc.3` é uma tag anotada e não assinada para consumo Git sobre o cohort
completo de dezesseis pacotes. Ela é protegida contra alteração e exclusão. Não
é GitHub Release, publicação no pub.dev nem o futuro canal formal assinado.

## Adicione pacotes

Mantenha declarações normais de versão para deixar explícito o cohort desejado,
e sobrescreva cada pacote selecionado e dependência Dartitect transitiva para o
mesmo repositório e tag:

```yaml
dependencies:
  dartitect_flutter: 1.0.0-rc.3

dependency_overrides:
  dartitect:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      ref: v1.0.0-rc.3
      path: packages/dartitect
  dartitect_flutter:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      ref: v1.0.0-rc.3
      path: packages/dartitect_flutter
```

Não misture dependências `path:` locais, outra ref Dartitect ou pacotes
Dartitect hosted na mesma resolução.

## Gere o fechamento transitivo

Em um clone deste repositório, emita um bloco de overrides pronto para colar
para um ou mais pacotes:

```console
dart run tool/git_dependency_overrides.dart dartitect_flutter
dart run tool/git_dependency_overrides.dart dartitect_media,dartitect_privacy
```

O gerador lê a ordem de publicação dos dezesseis pacotes e seus pubspecs,
percorre todas as dependências internas, rejeita pacotes desconhecidos e emite
uma URL/ref comum com o path Git relativo de cada pacote.

## Verifique a resolução

Execute `flutter pub get` e inspecione `pubspec.lock`: todo pacote resolvido cujo
nome começa com `dartitect` deve ter `source: git`, a mesma URL, a ref
`v1.0.0-rc.3` e o path `packages/<nome>`. A configuração de pacotes deve apontar
para o cache Git do Pub, nunca para um checkout Dartitect local.

Mantenedores validam os consumidores minimal, offline-first e de capacidades
nativas com:

```console
dart run tool/run_git_canaries.dart \
  --repository=https://github.com/ftr-tuta/dartitect.git \
  --ref=v1.0.0-rc.3
```

O gate rejeita tag ausente/lightweight, commit misto, qualquer pacote Dartitect
hosted e resolução por path local. A evidência nativa vem dos jobs hospedados de
emulador/simulador dentro de `CI / Required`.
