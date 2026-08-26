# Dartitect Locale BR

[Português (Brasil)](README.pt-BR.md)

## Purpose

`dartitect_locale_br` provides one dependency-free structural CEP value. The
1.0 surface intentionally excludes CPF, CNPJ, telephone, currency, address
lookup, and input widgets.

The eight-ASCII-digit and common display forms were reviewed on 2026-08-25
against the official [Correios Busca CEP](https://buscacepinter.correios.com.br/app/endereco/index.php)
interface. Structural validity does not prove that a CEP exists, is assigned,
accepts delivery, or belongs to an address. This package has no Correios or
online-database integration.

## Usage

```dart
final cep = BrazilianPostalCode.parse('79002-072');
print(cep.digits);     // 79002072
print(cep.formatted);  // 79.002-072
print(cep.hyphenated); // 79002-072
```

Use `tryParse` for untrusted input. Strict construction throws
`FormatException`; visually similar Unicode digits are rejected.

## Boundary contract

- Why a package: keep a Brazil-specific value outside locale-neutral core.
- Owns: one copied immutable string value; borrows and persists nothing.
- Logs: nothing; input values are never telemetry.
- Supports: structural parsing and formatting of CEP only.
- Does not support: existence/delivery validation, lookup, or other documents.
- Removal: remove the dependency and replace the value at the consumer boundary;
  no state or artifact migration is required.
