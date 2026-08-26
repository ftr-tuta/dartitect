# Dartitect Locale BR

[English](README.md)

## Objetivo e fonte

`dartitect_locale_br` fornece um único valor estrutural de CEP, sem
dependências. A superfície 1.0 exclui intencionalmente CPF, CNPJ, telefone,
moeda, consulta de endereço e widgets de entrada.

As formas de oito dígitos ASCII e de exibição comuns foram revisadas em
2026-08-25 contra a interface oficial [Busca CEP dos Correios](https://buscacepinter.correios.com.br/app/endereco/index.php).
Validade estrutural não prova existência, atribuição, entrega nem vínculo com
um endereço. O package não integra Correios ou base online.

## Uso

```dart
final cep = BrazilianPostalCode.parse('79002-072');
print(cep.digits);     // 79002072
print(cep.formatted);  // 79.002-072
print(cep.hyphenated); // 79002-072
```

Use `tryParse` para entrada não confiável. A construção estrita lança
`FormatException`; dígitos Unicode visualmente semelhantes são rejeitados.

## Contrato do boundary

- Razão do package: manter valor específico do Brasil fora do core neutro.
- Owns: uma string imutável copiada; não borrows nem persists nada.
- Logs: nada; valores de entrada nunca entram em telemetria.
- Supports: somente parsing e formatação estrutural de CEP.
- Does not support: existência/entrega, consulta ou outros documentos.
- Remoção: remova a dependência e substitua o valor no boundary do consumidor;
  não há estado nem artifact para migrar.
