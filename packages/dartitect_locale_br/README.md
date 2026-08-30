# dartitect_locale_br

## Purpose

One dependency-free immutable Brazilian postal-code (CEP) value with strict
structural parsing and formatting. The package intentionally contains no
network lookup, widgets, or other Brazilian document/value types.

## When to use

Use it at an application boundary that needs a normalized eight-ASCII-digit CEP
and the documented common display forms.

## When not to use

Do not use it to prove that a CEP exists, is assigned, accepts delivery, or
belongs to an address. It does not support address lookup, Correios integration,
CPF, CNPJ, telephone, currency, or input widgets.

## Platforms and entrypoints

Import `package:dartitect_locale_br/dartitect_locale_br.dart`. It is
dependency-free pure Dart and supports the Dart VM, Flutter, and web.

## Mental model and data flow

Untrusted text enters through `tryParse` or strict `parse`. The value trims
surrounding whitespace, accepts exactly eight ASCII digits or the documented
`XXXXX-XXX`/`XX.XXX-XXX` forms, stores a copied normalized digit string, and
exposes stable formatted representations. It performs no I/O and emits no logs.

## Minimal workflow

```dart
import 'package:dartitect_locale_br/dartitect_locale_br.dart';

void main() {
  final postalCode = BrazilianPostalCode.parse('79002-072');
  assert(postalCode.digits == '79002072');
  assert(postalCode.formatted == '79.002-072');
  assert(postalCode.hyphenated == '79002-072');
}
```

Use `BrazilianPostalCode.tryParse` when invalid external input should return
`null` instead of throwing.

## Public API tour

`BrazilianPostalCode` is the complete public surface: strict `parse`, nullable
`tryParse`, normalized `digits`, `formatted`, `hyphenated`, equality, hashing,
and string representation.

## Ownership and lifecycle

Each value owns one immutable copied string. It borrows and persists nothing and
has no lifecycle or disposal responsibility.

## Failure, cancellation, and concurrency

Strict parsing throws `FormatException` for malformed input; `tryParse` returns
`null`. There is no asynchronous work, cancellation, mutable state, or
concurrency coordination. Immutable values are safe to share normally.

## Prohibited uses and limitations

Unicode look-alike digits are rejected. Structural acceptance, including
`00000000`, makes no existence/delivery claim. Never log raw or normalized CEP
through this package. The accepted forms were reviewed against the official
Correios Busca CEP interface on 2026-08-25; that review is not an online
validation service.

## Testing

Run `dart test`. Cover accepted plain/hyphenated/dotted forms, whitespace,
non-ASCII digits, lengths, punctuation, formatting, equality/hash, fuzz input,
and absence of I/O or telemetry.

## Related packages and guides

This is a removable locale-specific leaf with no runtime dependency. Read
[optional capabilities](../../docs/guides/optional-capabilities.md) and
[ecosystem selection](../../docs/guides/ecosystem-selection.md). The reviewed
reference is [Correios Busca CEP](https://buscacepinter.correios.com.br/app/endereco/index.php).

## Availability

The workspace contains the `1.0.0-rc.8` source candidate. Use only coordinates
from a matching tag with a published GitHub Release and compatible cohort. If no
such Release exists, there is no supported consumption path. See the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md).
