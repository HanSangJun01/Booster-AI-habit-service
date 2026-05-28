<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-05-28 | Updated: 2026-05-28 -->

# ai-service

## Purpose
AI model integration layer responsible for habit verification and coaching. Receives evidence submissions (photos, text, sensor data) from `backend/` and returns verification verdicts and feedback. This is the core differentiator of the Booster product. Currently a placeholder directory — implementation not yet started.

## Key Files

| File | Description |
|------|-------------|
| `.gitkeep` | Placeholder to track this directory in git until implementation begins |

## Subdirectories
None currently.

## For AI Agents

### Working In This Directory
- Consult `../docs/project-plan.md` before starting implementation to understand the verification requirements
- Remove `.gitkeep` when real files are added
- Regenerate `ai-service/AGENTS.md` (via `/oh-my-claudecode:deepinit`) once the directory structure is established
- This service should be stateless — all persistence is handled by `../backend/`
- Expose a well-defined API (REST or gRPC) that `../backend/` consumes; never call backend directly

### Testing Requirements
- To be defined when the AI framework is chosen
- Plan for model evaluation tests separate from unit tests (accuracy, latency, edge cases)

### Common Patterns
- To be defined when implementation begins
- Expected patterns: prompt templates, model inference wrappers, result schemas

## Dependencies

### Internal
- Called by `../backend/`; no dependency on `../frontend/`

### External
- To be determined — likely Anthropic Claude API, OpenAI, or a local model runtime

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
