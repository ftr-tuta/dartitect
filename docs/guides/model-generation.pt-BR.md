# Geração de modelos Dartitect

[English](model-generation.md)

## Escopo 1.0 e contrato do source

A geração de modelos se limita a boilerplate de values imutáveis. O gerador
varre `lib/**` e cada árvore imediata `packages/*/lib/**` sem seguir symlinks.
Uma library anotada pode conter modelos na unit de definição e em parts; todos
os modelos compartilham um único part Dartitect determinístico.

| Contrato | Forma suportada em 1.0 | Forma rejeitada |
|---|---|---|
| Annotation | `@DartitectValue()` resolvido para o elemento de `package:dartitect_modeling`, inclusive por prefixo e reexport | Annotations homônimas ou não resolvidas |
| Classe | `final` concreta, estende `ValueEquality` e aplica `_$TypeDartitect` | Abstrata, não final ou com herança complexa |
| Part | Exatamente um `part '<source>.dartitect.g.dart';` | Part ausente, duplicado ou incompatível |
| Campos | Ao menos um campo público, tipado, nomeado e `final` no primary constructor | Campos privados, inferidos, positional, late ou mutáveis |
| Collections | Wrappers imutáveis de classe pertencentes ao consumidor | Interfaces de collection mutáveis, inclusive aliases de `List`, `Set`, `Map`, `Iterable`, queues, collections hash/tree e listas typed-data |
| Construtor | Um primary constructor sem nome; use `class const` quando construção constante for necessária | Formas tradicionais, primary named, somente factory, external ou positional |
| Forma da library | Múltiplos modelos, generics com bounds, const/defaults, records e parts comuns | Um part gerado por modelo ou acesso do renderer a AST/types não resolvidos |

O gerador não cria JSON, unions, schemas de DTO/entity, entities ObjectBox,
injeção de dependência, ViewModels, rotas, clients REST, reflexão runtime nem
modelos mutáveis. Outros geradores podem coexistir somente quando possuem
arquivos de saída distintos.

Primary constructor ausente produz `DT1030` e nenhum output de modelo é
aplicado. A identidade da annotation é semântica, não uma comparação de nome
lexical. O compiler read-only compartilhado possui um único lifecycle do
Analyzer e produz o mesmo IR público, regras granulares `DT1030+`, localizações,
severities e fix IDs para CLI e lints oficiais. O renderer recebe somente IR
validado.

Execute `dartitect model migrate primary` para um preview sem escrita da edição
semântica de values tradicionais elegíveis. Somente `--apply` adquire o lock
compartilhado, grava o journal próprio de source, revalida os bytes e commit ou
faz rollback da edição completa. Classes comportamentais e construtores
ambíguos exigem revisão do consumidor e nunca são reescritos por heurística.

## Equality gerada e `copyWith`

O mixin emite getters abstratos, `equalityFields` completo e `copyWith` tipado:

| Input | Campo nullable | Campo non-nullable |
|---|---|---|
| Omitido | Preserva | Preserva |
| Valor não nulo | Substitui | Substitui |
| `null` explícito | Preserva | Não substitui |
| `clear<Field>: true` | Limpa para `null` | Não existe parâmetro clear |
| Valor e clear juntos | Lança `ArgumentError` | Não se aplica |

`ValueEquality` exige o mesmo tipo runtime e compara campos na ordem estável de
declaração. Lists preservam ordem; sets e maps ignoram ordem; lists, sets e maps
aninhados são estruturais. Records e outros values usam seu próprio contrato de
igualdade. Values iguais recebem hashes iguais. Grafos cíclicos de collections
lançam `CyclicValueException` em equality e hashing.

Use esse contrato para values pequenos, imutáveis e acíclicos. Use
`immutableListCopy`, `immutableSetCopy` ou `immutableMapCopy` antes de reter
inputs de collections. Collections grandes, entities e snapshots devem usar
identidade, versão/projeção ou hash pré-calculado.

## Commands, freshness e ownership no Git

| Command | Escreve | Recovery | Comportamento de saída |
|---|---:|---:|---|
| `dartitect model sync` | Não; preview por padrão | Informa recovery pendente | 0 quando fresh, 1 para findings |
| `dartitect model sync --dry-run` | Não | Informa recovery pendente | 0 quando fresh, 1 para findings |
| `dartitect model check` | Nunca | Informa recovery pendente | 0 quando fresh, 1 para findings |
| `dartitect model sync --apply` | Sim, atomicamente | Recupera, redescobre, recalcula o plano e aplica | 0 no sucesso, 1 para findings de modelo |
| `dartitect model migrate primary` | Não; preview por padrão | Informa seu próprio journal de source pendente | 0 quando não resta migração, 1 para preview/findings |
| `dartitect model migrate primary --apply` | Sim, atomicamente | Faz rollback de source incompleto antes de redescobrir | 0 no sucesso |

Os dois commands aceitam `--json`. O exit code global 2 indica falha de uso ou
configuração, e 3 indica falha de I/O ou interna. Preview, dry-run e check nunca
reparam arquivos nem resíduos de recovery.

Versione todos os `*.dartitect.g.dart` e `.dartitect/model-outputs.json`. O CI
executa `dartitect model check` e rejeita qualquer diff gerado. Um checkout
limpo deve analisar, testar e compilar consumidores sem instalar nem invocar
`dartitect_cli`.

| Estado do plano | Significado | Regra de diagnóstico/apply |
|---|---|---|
| `create`, `update`, `delete` | Output owned ausente, stale ou órfão | `DT1020`; aplica o conjunto desejado completo |
| `noOp` | Bytes do output e ownership no manifest estão atuais | Fresh; nenhuma escrita |
| `conflict` | Ownership não pode ser provado | `DT1022`; preserva todos os bytes do consumidor e aborta a transação |
| Journal pendente | Transação interrompida exige recovery | `DT1023`; somente `sync --apply` pode recuperar |

LF é canônico nos bytes gerados; conteúdo CRLF equivalente é considerado
atual. Paths devem ser relativos ao projeto, não podem atravessar symlinks nem o
limite do workspace, e outputs unmanaged/corrompidos nunca são adotados. Não
existe flag force.

## Manifest, schemas e recovery

O manifest possui somente outputs inteiramente gerados e registra source,
versão do gerador, schema de input e digests SHA-256 canônicos de input/output.
Updates e deletes exigem que os bytes existentes correspondam ao digest
registrado.

| Artefato | Schema 1.0 | Regra de compatibilidade |
|---|---:|---|
| Assinatura semântica de input do modelo | 2 | Inclui identidade da library, capabilities, generics, defaults, types e todos os modelos do part gerado |
| Relatório JSON do command | 1 | Consumidores devem selecionar explicitamente o schema suportado |
| `.dartitect/model-outputs.json` | 1 | Ownership ausente conflita com outputs candidatos; schemas malformados, anteriores ou futuros falham fechado |
| `.dartitect/generation-journal.json` | 2 | Schemas malformados, anteriores ou futuros interrompem recovery e preservam resíduos para diagnóstico |

Não existe migração, downgrade ou force implícito. Mudança de schema exige uma
implementação explícita de compatibilidade e nova evidência de contrato.

O apply prepara a geração completa em staging, persiste um recovery journal,
faz backup dos targets owned, substitui outputs, substitui o manifest, valida os
digests commitados e remove os resíduos da transação. Fault tests cobrem cada
transição. Antes do commit, recovery restaura os bytes originais exatos e remove
targets recém-criados. Após a fase committed, recovery valida a nova geração e
finaliza cleanup. Bytes alterados concorrentemente são preservados e informados,
sem overwrite. Recovery e retry são idempotentes.

## Envelope de performance congelado

O artefato de referência Linux registra cinco execuções cold por cenário. As
medianas e o maior RSS observado são:

| Modelos | Command | Mediana | Peak RSS | Budget rígido |
|---:|---|---:|---:|---:|
| 100 | sync | 4.761.902 µs | 725.803.008 B | 15 s / 1 GiB |
| 100 | check | 2.799.851 µs | 740.970.496 B | 15 s / 1 GiB |
| 500 | sync | 9.911.425 µs | 732.372.992 B | 60 s / 1 GiB |
| 500 | check | 6.497.860 µs | 765.853.696 B | 60 s / 1 GiB |

`dart run tool/check_model_benchmark.dart` aplica os budgets rígidos e a
evidência de cinco runs. Regressão acima de 25% ou substituição de benchmark ou
budget exige revisão registrada. O envelope de performance validado termina em
500 modelos; workspaces maiores não possuem garantia de performance em 1.0.

Execute `dartitect model check`, `dart analyze`, os testes dos packages e o gate
de benchmark em checkout limpo. Confirme também que arquivos JSON/ObjectBox
gerados por providers não colidem. Use `$dartitect-modeling` para orientação de
implementação e revisão.
