---
name: dartitect-ui
description: Build business-neutral Flutter presentation around Dartitect state using consumer-owned Material or Cupertino controls, adaptive layouts, accessibility, localization, focus, navigation, forms, and UI tests. Use for Flutter UI implementation or review; do not use to invent an SDK design system.
---

# Build Dartitect presentation

## When to use

Use this skill when a Flutter consumer needs to render Dartitect commands,
forms, queries, effects, or reactive resources; choose responsive layouts;
design navigation and focus; or establish semantic, keyboard, accessibility,
and UI-matrix tests.

## When not to use

Use `$dartitect-runtime` for ownership and ViewModel design,
`$dartitect-reactive` for resource behavior, and `$dartitect-testing` for
non-UI lifecycle matrices. Do not create Dartitect-branded buttons, fields,
switches, dialogs, navigation, themes, copy, localization, or visual tokens.

## Invariants

The consumer owns `ThemeData`, `ColorScheme`, component themes,
`ThemeExtension`, typography, visible text, localization, navigation, brand,
and product composition. Use official Material 3 controls directly; use
adaptive or Cupertino controls only for established platform conventions.
Choose layout from finite available space, never device labels or orientation.
Keep ViewModels, controllers, focus nodes, navigation state, and restoration
above responsive branch replacement. Dartitect builders borrow state and never
dispose it.

## Workflow

1. Identify the authoritative command, form, query, effect, or resource. Do not
   introduce another async envelope.
2. Keep product state and actions in a ViewModel/controller above the layout;
   drain one-shot effects at the mounted View boundary.
3. Build controls directly from Material 3. Use `.adaptive` or Cupertino only
   when Flutter or an Apple convention defines a meaningful difference.
4. Use `DartitectResponsiveWindowBuilder` for the full surface and
   `DartitectResponsiveRegionBuilder` for a finite nested region. Supply all
   compact, medium, and expanded branches.
5. Render every state with `CommandStateBuilder`,
   `DartitectFormSnapshotBuilder`, `DartitectQueryStateBuilder`, or
   `ResourcePresentationBuilder`. Preserve stale content when the domain policy
   calls for it and distinguish expected failure from crash.
6. Localize all visible labels and semantics. Define traversal order, initial
   focus, shortcuts, and restoration in consumer code; keep actions reachable
   without pointer input.
7. Test the paired `DartitectUiMatrix`, then add product-specific focus,
   keyboard, navigation, and action assertions.

Read [references/presentation.md](references/presentation.md) for state,
responsive layout, navigation, forms, focus, and effects. Read
[references/verification.md](references/verification.md) for semantics,
accessibility, matrix, audit, and golden guidance.

## Validate

Run Flutter analyze/tests plus `dartitect ui audit --strict`. Prove all size
classes, 100%/200% text, LTR/RTL, light/dark, high contrast, reduced motion,
semantics, focus, keyboard activation, expected failures, crashes, stale and
empty states. Keep golden coverage small and secondary to behavior. Tests and
audits must not upload screenshots, semantics, or screen content.

## Dartitect inclusion gate

Before adding a capability, answer:

> Is it business-neutral, difficult to implement correctly, and a source of
> repetitive infrastructure in consumer applications?

All three answers must be “yes”. Otherwise reusable infrastructure belongs in
a typed project-local extension and business behavior stays in the application.
