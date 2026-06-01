# AGENTS.md

## Workflow Orchestration

### 1. Plan Mode Default

- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately - don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy

- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One tack per subagent for focused execution

### 3. Self-Improvement Loop

- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done

- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)

- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes - don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing

- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests - then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.

## Agent Roles

Each domain has a dedicated skill file. Spawn a subagent with the relevant SKILL.md as context.

| Agent | Skill file | Owns |
|---|---|---|
| **Hasura** | `.agents/skills/hasura-graphql-engine/SKILL.md` | `hasura/metadata/`, `hasura/migrations/` |
| **NestJS** | `.agents/skills/nestjs/SKILL.md` | `nestjs/src/` |
| **Infra** | `.agents/skills/infra/SKILL.md` | `docker-compose*.yml`, `install.sh`, `bootstrap.sh`, `Makefile` |

### Handoff Protocol

When work crosses domain boundaries:

- **NestJS adds a new action** → must also update Hasura metadata (`actions.yaml`, `actions.graphql`). Coordinate with Hasura agent or handle in same task.
- **Infra adds a new env var** → NestJS agent must update the service to read it via `configService`.
- **Hasura adds a new table** → Infra agent may need a migration; NestJS agent may need a new event handler.

### Verification Gate

Every agent must run `make test` before marking a task complete. If tests fail, fix before handing off.

## Resources

- Hasura skill: `.agents/skills/hasura-graphql-engine/SKILL.md`
- NestJS skill: `.agents/skills/nestjs/SKILL.md`
- Infra skill: `.agents/skills/infra/SKILL.md`
