<!-- Generated: 2026-05-28 | Updated: 2026-05-28 -->

# Booster AI Habit Service

## Purpose
Booster is an AI-powered habit completion service that uses verification-based accountability. The project is structured as a monorepo with three separate services: a frontend client, a backend API, and an AI service for habit verification and coaching.

## Key Files

| File | Description |
|------|-------------|
| `README.md` | Project overview (Korean: AI 검증 기반 습관 완주 서비스) |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `frontend/` | Client-facing application (see `frontend/AGENTS.md`) |
| `backend/` | API server and business logic (see `backend/AGENTS.md`) |
| `ai-service/` | AI model integration for habit verification (see `ai-service/AGENTS.md`) |
| `docs/` | Project documentation and planning (see `docs/AGENTS.md`) |
| `.claude/` | Claude Code / OMC configuration (CLAUDE.md, skills) |

## For AI Agents

### Working In This Directory
- This is a monorepo root — do not add application code here
- Each service (`frontend/`, `backend/`, `ai-service/`) is independently deployable
- Consult `docs/project-plan.md` for roadmap and feature scope before implementing
- When adding a new top-level directory, also create its `AGENTS.md`

### MVP Design Document References

When working on database design, ERD structure, API contracts, backend architecture, DTOs, controllers, services, or request/response formats, agents must refer to the following documents first:

| Document | Path | Purpose |
|----------|------|---------|
| MVP ERD | `docs/erd/MVP_ERD.md` | Defines MVP database tables, relationships, derived data, and ERD scope |
| MVP API Spec | `docs/api/MVP_API_SPEC.md` | Defines MVP API endpoints, request bodies, response formats, and API naming conventions |

### Rules for Using MVP Documents
- Use `docs/erd/MVP_ERD.md` as the source of truth for database tables, relationships, and ERD-level decisions.
- Use `docs/api/MVP_API_SPEC.md` as the source of truth for API endpoints, request/response fields, DTO design, and controller structure.
- Keep database column names and API field names aligned in `snake_case` unless there is a clear implementation reason not to.
- If the ERD and API spec conflict, do not make assumptions. Report the conflict first and ask for confirmation before modifying code or documentation.
- Do not add features outside the MVP scope unless they are explicitly requested.
- Treat leaderboard, calendar summaries, rankings, progress rates, and similar aggregate values as derived data unless the ERD document states otherwise.
- When adding or modifying backend code, check both documents before creating entities, DTOs, repositories, services, or controllers.

### Testing Requirements
- Run tests per-service from within each service directory
- CI should validate all three services independently

### Common Patterns
- Service boundaries are strict: no cross-imports between `frontend/`, `backend/`, and `ai-service/`
- Shared types or contracts (if any) should live in a dedicated `shared/` or `packages/` directory

## Dependencies

### Internal
- `frontend/` depends on `backend/` API endpoints
- `backend/` depends on `ai-service/` for verification logic
- `ai-service/` is standalone (no dependency on other services)

### External
- To be determined as each service is implemented

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
