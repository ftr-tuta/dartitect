# Dartitect Privacy

[English](README.md)

## Objetivo e suporte

`dartitect_privacy` é um boundary removível e exclusivo de ATT no iOS.
Construção e bootstrap são inertes; `request()` ocorre apenas por ação explícita
do consumidor. Versões iOS sem ATT e plataformas não iOS retornam
`notSupported`.

Este package não é engine de consentimento e não promete LGPD, GDPR, base
legal ou compliance regulatório.

## Contrato do boundary

- Razão do package: isolar AppTrackingTransparency da foundation.
- Owns: coordenação do request por method channel; nenhum provider/recurso
  global.
- Borrows: registrar/channel do Flutter e fluxo explicativo do consumidor.
- Persists: nada.
- Logs: nada; status e ação do usuário não entram em telemetria aqui.
- Supports: somente status ATT e request explícito.
- Does not support: consentimento jurídico, policy de analytics, inicialização
  de SDK ou geração de descrição de privacidade.
- Remoção: remova registro/dependência e substitua o
  `TrackingAuthorizationService` injetado.

O aplicativo possui `NSUserTrackingUsageDescription`, texto, momento, revisão
jurídica e inicialização de qualquer SDK de tracking.
