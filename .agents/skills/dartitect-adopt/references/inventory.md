# Brownfield inventory

Record:

- app, session, route, and background-isolate composition roots;
- global singletons, service locators, clients, Stores, subscriptions, timers,
  commands, ViewModels, and error handlers;
- which resources are created, borrowed, disposed, or leaked at each root;
- domain/application contracts and infrastructure imports crossing inward;
- expected failure types versus unexpected exceptions;
- local versus remote data authority, queues/outboxes, retry and conflict rules;
- logging, error capture, tracing, redaction, and duplicate provider hooks;
- generated code and consumer-owned schemas that Dartitect must not replace.

Keep an evidence table with current behavior, owner, proposed boundary, test,
and rollback condition for each selected migration slice.
