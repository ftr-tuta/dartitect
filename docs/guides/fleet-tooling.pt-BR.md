# Tooling de frota

[English](fleet-tooling.md)

## Distribuição

Execute a CLI pela versão exata em dev dependency ou ative-a separadamente:

```console
dart run dartitect_cli:dartitect --version
dart pub global activate dartitect_cli 1.0.0-rc.4
```

Não adicione `dartitect_cli` às dependências de runtime da aplicação. Analyze e
build nunca ativam a CLI nem baixam policy de frota.

## Comandos read-only de frota

`--root` define a fronteira da frota. Cada root seguinte é explícito, relativo
a essa fronteira, ordenado no output e resolvido sem escape por symlink.

```console
dartitect fleet versions apps/a apps/b --root . --json
dartitect fleet check apps/a apps/b --root . --json
```

`versions` lê metadados de pubspec/lock sem invocar pub. `check` executa a mesma
verificação read-only de arquitetura, modelagem, ecossistema e providers de
`dartitect verify`, sem baseline. Ambos incluem `modelStatus` e
`providerStatus`; os paths permanecem relativos à frota.

## Policy offline fixada

A policy exige bundle local e seu digest SHA-256 minúsculo. O bundle fixa o
arquivo de policy por um segundo digest. URL ou download implícito não é aceito.

```console
sha256sum tool/fleet_policy_bundle.json
dartitect fleet policy apps/a apps/b \
  --root . \
  --bundle=tool/fleet_policy_bundle.json \
  --sha256=1bc7b8921f16a95a2712081289392f0c93f9883635869f4cf266e9567052f90c \
  --json
```

Recalcule o digest externo após uma mudança revisada do bundle; nunca reutilize
o digest do exemplo para bytes diferentes.

## Preview de upgrade

O upgrade de frota é intencionalmente apenas preview:

```console
dartitect fleet upgrade apps/a apps/b \
  --root . --dry-run --to=1.0.0-rc.4 --json
```

Cada resultado inclui operações sanitizadas, coorte alvo, manifest de inputs
semânticos e seu state token. O serviço de projeto reutilizável pode aplicar um
plano revisado sob lock do SO e journal recuperável do pubspec, mas a CLI de
frota não possui caminho `--apply`. Dependências estruturadas path/git/sdk e
constraints desconhecidas exigem revisão manual.

## SARIF

Use `dartitect verify --sarif` para o gate read-only completo, ou
`dartitect scan --sarif` somente para arquitetura. SARIF e JSON estável são outputs
separados; `--json` e `--sarif` são mutuamente exclusivos. SARIF usa URIs
relativas e mensagens sanitizadas e omite evidência de source e remediation.
