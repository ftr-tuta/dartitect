# Consumo do candidato Git

[English](git-candidate-consumption.md)

## Canal

`v1.0.0-rc.4` é o target anotado e não assinado preparado para consumo Git do
cohort completo de dezenove pacotes. Esta entrega de source não cria a tag,
GitHub Release nem publicação no pub.dev. Se autorizada depois, a tag deve ser
protegida contra alteração e exclusão.

## Adicione pacotes

Mantenha declarações normais de versão para deixar explícito o cohort desejado,
e sobrescreva cada pacote selecionado e dependência Dartitect transitiva para o
mesmo repositório e tag:

```yaml
dependencies:
  dartitect_flutter: 1.0.0-rc.4

dependency_overrides:
  dartitect:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      ref: v1.0.0-rc.4
      path: packages/dartitect
  dartitect_flutter:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      ref: v1.0.0-rc.4
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

O gerador lê a ordem de publicação dos dezenove pacotes e seus pubspecs,
percorre todas as dependências internas, rejeita pacotes desconhecidos e emite
uma URL/ref comum com o path Git relativo de cada pacote.

## Verifique a resolução

Execute `flutter pub get` e inspecione `pubspec.lock`: todo pacote resolvido cujo
nome começa com `dartitect` deve ter `source: git`, a mesma URL, a ref
`v1.0.0-rc.4` e o path `packages/<nome>`. A configuração de pacotes deve apontar
para o cache Git do Pub, nunca para um checkout Dartitect local.

Mantenedores validam os consumidores modeling, interop, minimal, offline-first,
Drift-provider e de capacidades nativas com:

```console
dart run tool/run_git_canaries.dart \
  --repository=https://github.com/ftr-tuta/dartitect.git \
  --ref=v1.0.0-rc.4
```

O gate rejeita tag ausente/lightweight, commit misto, qualquer pacote Dartitect
hosted e resolução por path local. A evidência nativa vem dos jobs hospedados de
emulador/simulador dentro de `CI / Required`.
