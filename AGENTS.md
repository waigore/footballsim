# Agent guide — Footballsim

## What this project is

Footballsim is a Football Manager–scale football world simulation. The player does **not** take charge of a club. They influence the world through god-like actions while simulation engines (especially matches) produce outcomes. The product is mostly UI-driven and built in **Godot**.

## Priorities

1. Simulation correctness and depth over flashy presentation
2. Clear separation: simulation core vs Godot UI / presentation
3. Reuse existing patterns before adding new modules or abstractions
4. Specs before large features (`SPEC/` or equivalent when introducing systems)

## Architecture expectations

- **Simulation engines** — deterministic or seedable where practical; testable without the UI
- **Godot** — scenes, screens, and wiring; thin orchestration that calls into simulation code
- **God-like actions** — model interventions as explicit inputs to the sim, not ad-hoc UI side effects
- Prefer extending shared types/services over duplicating league/match/player logic

## Implementation norms

- Follow Godot project conventions once the project is scaffolded (folder layout, naming, signals)
- Keep screens thin; put rules and state transitions in simulation modules
- Type and document public sim APIs; avoid `any`-style loose contracts at boundaries
- Unit-test engines and pure logic; keep UI tests light unless interaction is the risk

## Out of scope (for now)

- Traditional FM-style “manage this club” player mode
- Real licensed club/player data unless explicitly added later

## When unsure

Prefer simulation fidelity and a small, testable surface over premature tooling or extra layers.
