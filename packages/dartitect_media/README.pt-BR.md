# Dartitect Media

[English](README.md)

## Objetivo e suporte

`dartitect_media` é um plugin Android/iOS removível para status de autorização
da galeria, solicitação explícita e salvamento de imagem. Ele não fornece
picker, vídeo, editor, gerência de temporários nem camada ampla de mídia.

No Android API 24–28, o plugin persiste apenas se ele já iniciou a solicitação
legada de escrita, distinguindo `notDetermined` de `denied`. Android 29+ não
declara nem solicita escrita legada. No iOS 14+, o contrato 1.0 usa
deliberadamente Photos `.readWrite` em status, request e save, pois consulta e
criação de álbum opcional exigem acesso à biblioteca; `.limited` é preservado e
não satisfaz o salvamento.

## Uso

Crie `MethodChannelGalleryMediaService` na composição de infraestrutura.
Solicite acesso somente por uma ação explícita da UI do consumidor; depois
passe a `saveImage` um path absoluto legível pelo nativo e álbum opcional. Save
nunca solicita permissão automaticamente. Completions nativas voltam ao Flutter
na main thread.

## Contrato do boundary

- Razão do package: isolar MediaStore/Photos e suas dependências nativas da
  foundation.
- Owns: coordenação do method channel e o bit Android de request já tentado.
- Borrows: path e arquivo de entrada; nunca remove nem edita ambos.
- Persists: somente esse bit de histórico Android; o asset é persistido pela
  galeria da plataforma.
- Logs: nada. Paths, nomes, bytes, álbuns e mensagens nativas nunca entram em
  telemetria.
- Supports: status, request, uma imagem, álbum opcional e remoção do bit owned
  de histórico de autorização em Android/iOS.
- Does not support: picker, vídeo, edição, cleanup temporário, desktop ou web.
- Remoção: enquanto o plugin Android ainda estiver instalado, aguarde
  `clearOwnedState()` para apagar o bit de histórico de autorização. Depois
  remova dependência/registro e substitua o `GalleryMediaService` injetado. O
  cleanup é inerte nos demais hosts e nunca revoga permissão do OS nem apaga
  source files/assets da galeria; assets existentes permanecem owned pela
  plataforma/pessoa usuária. Se o cleanup retornar `cleanup_failed`, mantenha o
  plugin instalado e tente novamente em vez de declarar resíduo zero.

O aplicativo possui textos e descrições nativas, usage descriptions do
`Info.plist`, nome do álbum, lifetime/cleanup do source, mensagens ao usuário e
revisão de plataforma.
