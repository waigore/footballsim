# Requirement pack (chat confirm)

Show the owner this shape before filing. Omit or mark **not affected** for
unused dimensions. Keep the main text plain English.

```markdown
## Theme
<one feature theme>

## Functional
- Behavior: <what must happen>
- Out of scope: <explicit non-goals, or none>
- Acceptance (player-visible): <bullets>

## Non-functional (game/sim budgets)
- Tick / sim cost: <target or not affected>
- UI responsiveness: <target or not affected>
- Save / load: <impact or not affected>
- Desktop + mobile: <both | scoped | not affected>
- Other budgets: <… or not affected>

## UX
- Surfaces / flows: <screens, panels, inputs>
- Streamlined UX criticality: <high | medium | low> — <why>
- Touch + mouse/keyboard: <notes or not affected>

## Architectural
- Owner intent: <where they think it lives>
- Proposed components: <modules/scenes/autoload — from codebase skim>
- Sequences: <who calls whom; happy path>
- Data: <stored/retrieved where>
- Conflicts / risks: <vs current architecture, or none>

## Algorithmic / schematic
- Formulas / calculations: <or not affected>
- Data schema: <fields/entities or not affected>
- Determinism / seed notes: <or not affected>

## Open questions
- <gaps to resolve before or via question issues>

## Wiki
- Status: <matches | silent | conflicts> — <pages>
- Follow-up proposed: <yes/no — awaiting owner confirm>

## Filing plan
- Ambiguity mode: <todo+enhancement | question>
- Container + subs: <titles>, or <single issue>
```

Optional short `## For agents` only after owner confirm, when filing:

```markdown
## For agents
- REQ / RUB (if known): <ids or none>
- Pack dimensions covered: <list>
- Related open issues checked: <none or #N…>
```
