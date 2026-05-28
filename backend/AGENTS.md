<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-05-28 | Updated: 2026-05-28 -->

# backend

## Purpose
API server and business logic layer for the Booster habit service. Handles user authentication, habit management, verification orchestration, and persistence. Bridges the `frontend/` client with the `ai-service/` verification engine. Currently a placeholder directory — implementation not yet started.

## Key Files

| File | Description |
|------|-------------|
| `.gitkeep` | Placeholder to track this directory in git until implementation begins |

## Subdirectories
None currently.

## For AI Agents

### Working In This Directory
- Consult `../docs/project-plan.md` before starting implementation to align with planned architecture
- Remove `.gitkeep` when real files are added
- Regenerate `backend/AGENTS.md` (via `/oh-my-claudecode:deepinit`) once the directory structure is established
- Do not import directly from `../frontend/` — this service exposes an API, it does not depend on clients
- Calls to `../ai-service/` should go through a defined interface (REST, gRPC, or message queue)

### Testing Requirements
- To be defined when the backend framework is chosen
- Plan for integration tests covering API contracts with both frontend and ai-service

### Common Patterns
- To be defined when implementation begins

## Dependencies

### Internal
- Calls `../ai-service/` for habit verification results
- Consumed by `../frontend/`

### External
- To be determined (likely Node.js/NestJS, Python/FastAPI, or similar)

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
