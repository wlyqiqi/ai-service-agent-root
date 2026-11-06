# Product

## Audience

- Primary user: household customers of a Qingdao-origin global smart home brand who need product setup, order, service, and human escalation support.
- Key moment: arriving customers should immediately understand the brand is global, intelligent, and trustworthy before contacting AI support.

## Capabilities

- Login with phone number and password against the existing `/auth/login` API.
- Create an authenticated service session through the existing `/sessions` API.
- Launch the Chatwoot/WootChat widget as the AI-service surface. It is a hosted black box at the code level; we extend its visual and seat-side behavior through documented CSS/JS injection points, not by forking the image (`docs/ops/chatwoot-widget-form.md`, `docs/adr/0006-seat-approval-card-hitl.md`).
- Preserve auth/session behavior, fallback mock behavior, and redirect semantics.

## Constraints

- Do not fork, patch the image source, or reimplement Chatwoot internals. Extend it only via the CSS/JS injection points in `docs/ops/chatwoot/`; re-apply overrides after a Chatwoot upgrade.
- This frontend surface must not change agent, LangGraph, router, runtime, or business logic. Backend/runtime changes belong to their own PRs and specs.
- Keep the user-facing surface premium, spatial, global, and cinematic while avoiding generic AI-SaaS styling.

## Platform

- Web, delivered as the static frontend entrypoints `web/landing.html` / `web/landing-v2.html`. The former `web/index.html` was removed when `docs/specs/user-page-spec.md` was deprecated (2026-10-14).
