# Config v1 estável

[English](config-v1.md)

## Contrato

`dartitect.json` aceita exatamente `configVersion: 1` com o perfil
`native_strict`. Ele declara globs de camadas, raízes de composição,
infraestrutura gerada, suppressions revisadas, os cinco blueprints
generated-once e blocos opcionais `modeling` e `ecosystem`. Também pode
substituir a lista revisada de suffixes gerados. O scanner da CLI e o plugin do
analyzer compartilham as definições estáveis da policy.

Versões experimentais de configuração são intencionalmente incompatíveis. Não
há comando de upgrade nem migração: recrie o arquivo com `dartitect init` e
revise-o antes de substituir um experimento local antigo.

## Crie e valide

```console
dartitect init --dry-run
dartitect init
dartitect scan --no-baseline
dartitect doctor
```

O parser rejeita campos ausentes ou com tipo incorreto e preserva extensões v1
desconhecidas sem interpretá-las. Ele não armazena credenciais. Globs e raízes
são relativos ao repositório. Uma fonte é gerada por glob explícito ou pela
combinação de header padrão e suffix configurado. Config inválida no analyzer é
diagnóstico explícito; defaults nunca ocultam o estado inválido.

## Blocos RC4 aditivos

Omitir `modeling` preserva o comportamento dos consumidores config-v1
existentes. Quando presente, ele seleciona um preset de adoção e limites JSON
untrusted explícitos. `ecosystem` registra adoção incremental e trata runtime
overlapping instalado, mas sem vazamento, como warning:

```json
{
  "modeling": {
    "preset": "interop_existing_project",
    "jsonLimits": {
      "maxDepth": 64,
      "maxCollectionItems": 10000,
      "maxNodes": 100000
    }
  },
  "ecosystem": {
    "adoption": "incremental",
    "installedOverlap": "warning"
  }
}
```

Esse é um fragmento a integrar em um documento config-v1 completo. Extension
keys v1 desconhecidas continuam preservadas no round-trip, mas campos e enums
conhecidos dos blocos são validados de modo fail-closed.

## Presets não ativam annotations

`minimal` sugere apenas semântica de value. `recommended_complete` sugere
capabilities de value, JSON, projection e mapper para um modelo novo.
`interop_existing_project` permite generators consumer-owned coexistirem quando
possuem outputs diferentes. São apenas defaults de adoção: JSON, projections e
mappers ainda exigem annotations independentes. Nenhum preset autoriza
vazamento de provider, ownership duplicado, dual-write ou conversão inferida.

Execute `dartitect verify --json` após alterar qualquer bloco. Use `dartitect
verify --sarif` para ingestão em code scanning; ambas as formas são estritamente
read-only.

## Suprima deliberadamente

Cada suppression exige código, glob, motivo, responsável e data de expiração ou
justificativa permanente. Prefira corrigir o limite; use suppression somente
para dívida revisada ou exceção intencional. Entradas expiradas ou incompletas
não ocultam findings.
