# Contratos das capabilities opcionais

[English](optional-capabilities.md)

Os quatro packages de capability são folhas opt-in. Foundation, runtime,
observabilidade e tooling não dependem deles. Adicionar um package não seleciona
os demais, e remover um deles não altera formatos persistidos do core Dartitect.

## Matriz de boundaries congelada para 1.0

| Package | Plataforma suportada e outcome | Owns / borrows / persists | Logging | Supports | Does not support | Remoção |
|---|---|---|---|---|---|---|
| `dartitect_privacy` | Flutter iOS; deployment floor iOS 12, ATT disponível no iOS 14+. iOS anterior, Android, desktop, Fuchsia e web retornam `notSupported` sem channel call | Owns coordenação do request; borrows registro Flutter e fluxo explicativo do consumidor; não persists nada | Não emite logs; status, escolha e ação nunca são telemetria | Leitura de status ATT e request somente após chamada explícita do consumidor | Consentimento jurídico, promessas LGPD/GDPR, policy de analytics, inicialização de SDK ou geração de usage description | Substitua `TrackingAuthorizationService`, remova registro/dependência e só então remova `NSUserTrackingUsageDescription` se nenhum outro consumidor precisar dela. Sem migração de estado ou resíduo Dartitect |
| `dartitect_media` | Flutter Android API 24+ e iOS 14+. Desktop, Fuchsia e web retornam outcomes tipados de não suporte sem channel call | Owns coordenação de channel/request e um bit Android de histórico do request legado; borrows source path/file sem alterá-lo; assets salvos passam a ser owned pela plataforma/pessoa usuária | Não emite logs; paths, nomes, bytes, álbuns, mensagens nativas e receipts nunca são telemetria | Status, request explícito, save de uma imagem, álbum opcional e cleanup de metadata owned | Picker, vídeo, edição, gerência de temporários, mídia desktop/web ou requests automáticos de permissão | Aguarde `clearOwnedState()` enquanto o plugin Android estiver instalado, substitua `GalleryMediaService` e remova registro/dependência. Cleanup nunca revoga permissão nem apaga source/assets da galeria |
| `dartitect_locale_br` | Dart VM, Flutter e web | Owns uma string imutável copiada de dígitos ASCII; não borrows nem persists nada | Não emite logs; CEP bruto ou normalizado nunca é telemetria | Parse/formatação estrutural de CEP plain, `XXXXX-XXX` e `XX.XXX-XXX` | Existência, atribuição, entrega, lookup de endereço, integração Correios, CPF/CNPJ, telefone, moeda ou widgets | Substitua o value no boundary de locale e remova a dependência. Sem migração de estado/artifact |
| `dartitect_geometry` | Dart VM, Flutter e web | Owns cópias imutáveis das coordenadas; não borrows nem persists nada | Não emite logs; coordenadas e resultados nunca são telemetria | Pontos cartesianos 2D finitos, polygon/holes simples validados, polylabel determinístico, tolerância e precisão explícitas | GIS, CRS, projeção, geodesia, semântica de latitude/longitude, antimeridiano, conversão de unidades, geometry mutável ou reparo topológico | Substitua chamadas no adapter de geometry e remova a dependência. Sem migração de formato persistido ou recurso runtime |

## Regras de permissão e ação

Construção e composição são inertes. Ler status nunca mostra prompt.
`request()`/`requestAccess()` só podem ser chamados por interação explícita
owned pelo consumidor; bootstrap, construtor, leitura de status e image save
nunca solicitam permissão automaticamente.

`dartitect_privacy` preserva todos os estados ATT. Estado nativo futuro
desconhecido falha com o código estável `invalid_status` e não retém o payload
nativo.

`dartitect_media` congela este comportamento por plataforma:

| Host | Status/request | Contrato de save |
|---|---|---|
| Android API 24–28 | Declara/solicita `WRITE_EXTERNAL_STORAGE`; o bit de histórico owned pelo plugin distingue `notDetermined` inicial de `denied` | Exige autorização, copia uma imagem legível para MediaStore, remove asset parcialmente inserido em falha e conclui na main thread |
| Android API 29+ | Nunca declara nem solicita permissão legada de escrita; status é `authorized` para inserção no MediaStore | Usa MediaStore scoped com publicação pendente; source file permanece intacto |
| iOS 14+ | Usa Photos `.readWrite` em status/request porque lookup/criação do álbum opcional exige library access; preserva `.limited` | Exige `.authorized`; limited produz `GalleryLimitedAccessFailure`; a transação Photos cria um asset e associação opcional ao álbum; completion volta na main thread |
| Outros/web | `notSupported`, channel-inert | `Err(GalleryNativeFailure('not_supported'))`, channel-inert |

`saveImage` verifica status, mas nunca chama request. Falhas nativas esperadas
são mapeadas para falhas tipadas sem payload. `clearOwnedState()` apaga somente
a preference Android `legacy_write_requested`; é command de remoção/migração,
não dispose rotineiro. Um platform error `cleanup_failed` bloqueia a remoção e
deve ser tentado novamente; resíduo zero não pode ser declarado após essa falha.

O consumidor owns texto explicativo, usage descriptions, timing do request,
mensagens à pessoa usuária, lifetime/cleanup do source file, nomes de álbum,
revisão jurídica/de plataforma e inicialização de SDKs.

## Limites dos values Dart puro

`BrazilianPostalCode` aceita oito dígitos ASCII e as duas máscaras documentadas,
removendo whitespace externo. Aceitação estrutural, inclusive de `00000000`,
não afirma que o CEP existe, foi atribuído ou aceita entrega. A referência e a
data de revisão permanecem registradas no README do package.

`dartitect_geometry` trata coordenadas como unidades planares do input. Pontos
devem ser finitos e comparam exatamente. A construção do polygon copia/congela
rings e rejeita degeneração, self-intersection, holes fora/tocando o ring
externo e holes sobrepostos/aninhados. `defaultGeometryTolerance` é o bound
absoluto público `1e-12`; `precision` é finita, positiva, usa a unidade do input
e limita a melhoria restante do polylabel. Inputs e precision iguais produzem o
mesmo resultado.

## Verificação

Execute os testes dos dois packages Flutter e as duas suites Dart puro em VM e
Chrome. Contract tests cobrem construção inerte, hosts sem suporte, mapping de
status nativo, separação do prompt, falhas tipadas/sem payload, cleanup de estado
owned, limites de values, cópias imutáveis, validação numérica e determinismo.
Builds native floor/current e evidência runtime de permissões/lifecycle
permanecem no gate separado de hardening V1S-13.

No RC.2, o comportamento runtime Android é verificado somente em aparelho físico
Android 14/API 34. A API 24 Android é coberta por compatibilidade de
manifest/lint/build, não por emulador. iOS é coberto por builds com deployment
floor iOS 14 para media e iOS 12 para privacy, além de integração real de
method channels em simulador escolhido dinamicamente no GitHub Actions. iPhone
físico não é exigido nem alegado.
