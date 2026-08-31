# Presentation architecture

## State and actions

Treat existing authorities as final: `DartitectCommand` for an action,
`DartitectFormController` for form snapshots/submission,
`DartitectQueryController` for query state, `EffectChannel` for one-shot UI
effects, and `LiveResource` plus `ResourcePresentationState` for reactive local
authority. Do not wrap them in a second loading/error model. Builders borrow
controllers and resources, observe only while `TickerMode` is enabled, catch up
on reactivation, and never dispose what they receive.

Keep validation policy in the form controller and render official `TextField`,
`TextFormField`, selection, and button controls with localized labels, errors,
hints, and announcements. Keep submit commands exhaustive and prevent duplicate
submission through command policy rather than a widget-local flag.

Drain effects from a mounted View boundary. Navigation, snack bars, dialogs,
and platform intents are consumer presentation behavior; ViewModels emit typed
effects but do not retain `BuildContext`.

## Responsive layout and navigation

Use the Material 3 width thresholds 600 and 840 and height thresholds 480 and
900 unless the app supplies validated alternatives. An exact threshold belongs
to the larger class. Window classification records width and height separately;
branch selection uses available width. A nested region must have finite width.

The responsive builders choose no `Scaffold`, route, navigation control, color,
or copy, and they preserve no state implicitly. Put route state, selected
destination, scroll controllers, focus nodes, forms, and restorable state above
the branch. A consumer may select `NavigationBar`, `NavigationRail`, drawer,
split view, or a product-specific composition without changing domain state.

## Platform, focus, and localization

Prefer Material 3 everywhere. Choose `.adaptive` when Flutter provides it for
the same semantic control. Use Cupertino directly only for a deliberate Apple
convention, not as a wholesale platform fork. Do not infer layout from
`Platform`, device models, or orientation.

Every visible string, tooltip, semantic label, validation message, and action
name belongs to consumer localization. Use Flutter `Localizations`/gen-l10n and
locale-aware directionality. Define focus traversal and shortcuts explicitly
for dialogs, forms, split panes, menus, and desktop/web commands. Test keyboard
activation and restoration as product assertions rather than generic harness
behavior.
