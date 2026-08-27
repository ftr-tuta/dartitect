# Config v1 estável

[English](config-v1.md)

## Contrato

`dartitect.json` aceita exatamente `configVersion: 1` com o perfil
`native_strict`. Ele declara globs de camadas, raízes de composição,
infraestrutura gerada, suppressions revisadas e os cinco blueprints
generated-once. Também pode substituir a lista revisada de suffixes gerados. O
scanner da CLI e o plugin do analyzer compartilham as regras
`DT1001` a `DT1015`.

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

## Suprima deliberadamente

Cada suppression exige código, glob, motivo, responsável e data de expiração ou
justificativa permanente. Prefira corrigir o limite; use suppression somente
para dívida revisada ou exceção intencional. Entradas expiradas ou incompletas
não ocultam findings.
