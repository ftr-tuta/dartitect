# Ownership and isolates

The composition root creates dependencies from longest-lived to shortest-lived
and disposes them in reverse. Dispose bindings and commands, then subscriptions,
watchers and queries, then clients and Stores, then flush/dispose owned
observability. Consumer-owned providers close after all Dartitect borrowers.

Each isolate creates a fresh graph from transferable configuration. Validate
incoming trace context before using it. Never transfer a live client, Store,
owner, command, ViewModel, subscription, timer, or callback closure that captures
one. Close isolate-local resources in `finally`.
