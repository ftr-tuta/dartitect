# Política de segurança

[English](SECURITY.md)

## Versões suportadas

Correções miram o cohort lockstep de desenvolvimento/estável atual. Prereleases
antigas podem exigir upgrade.

## Reportando vulnerabilidade

Não abra issue pública. Use **Security → Advisories → Report a vulnerability**
no GitHub. Inclua pacote/versão, impacto, reprodução mínima, plataforma e
mitigação. Não inclua credenciais reais, dados de produção, DSNs, tokens ou
identidade.

Maintainers confirmarão o recebimento, coordenarão validação/correção e
divulgação. Não há garantia de prazo ou bounty.

## Limites de segurança

Dartitect não possui credenciais/config de fornecedores. MCP é local STDIO,
restrito a roots, read-only por padrão e sem shell/arquivo arbitrário. Trate
escritas opt-in e adapters como operações privilegiadas e revise dependências.
