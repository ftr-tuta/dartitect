# Dartitect adapters app

Adapters belong only to infrastructure/composition. Never expose Dio or
ObjectBox from domain contracts or import them in ViewModels. ObjectBox is
conditionally excluded from web code.
