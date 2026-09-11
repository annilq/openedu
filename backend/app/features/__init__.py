"""Feature-first backend packages (ADR-0027).

Each subpackage owns its router + schemas + repository + service for one business
capability. Shared ORM tables live in `app.db.models`; shared AI/domain infrastructure
(provider, safety, retriever, subjects) stays in `app.domain` (shared kernel).
"""
