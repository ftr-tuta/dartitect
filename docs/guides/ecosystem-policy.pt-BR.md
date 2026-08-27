# Política de dependências do ecossistema

[English](ecosystem-policy.md)

## Ledger global neutro

`tool/ecosystem_policy.json` schema v3 é a autoridade versionada do Native Strict. Ele
contém somente decisões válidas para o projeto inteiro; paths, exceções,
métricas e escolhas específicas de consumidores são proibidos nesse arquivo.
Cada registro separa decisão arquitetural, boundary revisado, maturidade,
compatibilidade e status atual de adoção pelo Dartitect. As decisões são:

- `approved`: revisado para o boundary documentado;
- `approved_primitive`: primitiva de baixo nível revisada sem adoção implícita;
- `advisory_alternative`: o Dartitect oferece alternativa limitada, mas o uso
  do package externo é apenas informativo por padrão;
- `reviewed_exception`: o uso exige overlay do consumidor com escopo;
- `prohibited_native_strict`: proibição universal de arquitetura, container,
  service locator, import privado ou segurança;
- `unreviewed`: ausente do ledger global.

Packages desconhecidos são advisory na auditoria de um consumidor. Eles
bloqueiam o release audit do próprio Dartitect até que o package resolvido
exato conste no inventário revisado do workspace.

`package:listen` é `approved_primitive` no boundary de primitiva Dart pura, mas
sua adoção está `deferred_until_real_consumer`. Ele não é dependência, reexport,
requisito de bridge nem motivo para criar `dartitect_state`.

## Overlay do consumidor

Aplicativos versionam suas escolhas em `.dartitect/ecosystem-policy.json`:

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "package": "pdf",
      "decision": "approved",
      "owner": "equipe da plataforma de documentos",
      "reason": "adapter isolado de renderização de documentos",
      "expiresOn": "2026-11-22",
      "paths": ["lib/infrastructure/documents/**"],
      "directOwners": ["document_adapter"]
    }
  ]
}
```

Uma entrada exige package, owner, motivo, expiração e ao menos um path não
global. `directOwners` é opcional, mas, quando presente, toda rota até um
transitivo deve começar em um desses owners. O overlay pode adicionar
approvals, advisories e exceções revisadas. Ele não pode desativar proibição
universal, autorizar publicação, mover tipos de provider entre camadas nem
conter segredos.

## Comandos e paridade

`dartitect dependencies audit` reporta todos os owners diretos e uma rota
resolvida determinística por owner. `dartitect dependencies explain <package>`
mostra a decisão global neutra. Use `--json` para automação.

DT1017 identifica conflito universal ou contextual; DT1018 identifica revisão
inválida, ausente, expirada ou incompleta. Alternativas como Freezed, Retrofit,
packages de UUID, plugins de galeria e tooling de splash nativo não geram erro
somente porque o Dartitect possui capability limitada equivalente. `sentry_dio`
vira erro apenas quando a instrumentação Dio equivalente do Dartitect também
estiver resolvida.

O comando de dependências, o scanner e o plugin do Analyzer usam as mesmas
decisões e o mesmo schema de overlay. O Analyzer incorpora snapshot gerado e
conferido; o gate rejeita decisão, alternativa, conflito ou proibição de
arquitetura desatualizada.

## Workflow de revisão

Atualize o ledger neutro somente para fatos válidos no projeto inteiro. Coloque
escolhas de aplicativo no overlay e execute audit de dependências, scanner,
testes do Analyzer, revisão de fontes/licenças, advisories, SBOM e gate de
freshness. Nunca use ignore global ou override para esconder falha de solver ou
policy.
