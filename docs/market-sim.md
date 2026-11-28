# Market sandbox

Run one market subsystem headless, against a scratch save built from the
shipped seed. The CLI prints; every rule lives in the verb's own module
([DR-20261128-31](https://github.com/waigore/footballsim/wiki/dr-20261128-31)).

## Commands

```bash
godot --headless --path . --script res://tools/market_sim.gd -- <verb> [flags]
```

Flags: `--seed`, `--clubs`, `--days`, `--expire`, `--seasons`, `--currency`,
`--json`-style output is the printed JSON line. The run exits `1` on a failed
invariant.

## Verbs

| Verb | Runs | Proves |
|------|------|--------|
| `season` | settle, archive, rollover | archives, ageing, idempotence |
| `contracts` | expiry, renewal, options | the bootstrap envelope, free agency |
| `windows` | the association calendar | open and closed by date alone |
| `ledger` | revenue, wages, amortisation, prize | ledger kinds, currency display |
| `deal` | one permanent move end to end | the validators, the commit, clearance |
| `ai` | a world season of AI deals | volume, spread, mode equivalence, no stranded club |
| `loan` | a loan split, trigger and return | registration, splits, caps, obligations |
| `clauses` | clause, sell-on, agent, solidarity | the money beyond the fee |
| `clearance` | a cross-association move | pending, failure, the window close |
| `youth` | ageing, retirement and intake for N seasons | the intake shape, the exit, names |
| `news` | scripted deals build the rumour feed | rumour threshold, news kinds, cap |
| `ui-fixture` | writes a canned market save | the market UI suites' shared world |

Each verb owns a file under `tools/market_sim/`; `tools/market_sim.gd` only
parses flags, loads the verb and prints its dictionary.

## The ai verb

```bash
godot --headless --path . --script res://tools/market_sim.gd -- ai \
  --clubs 172 --days 365 --mode fixture_days
```

It plays a season with the AI on and prints the signed count, value spread,
refusals and any stranded club. `--mode every_day` must print the same
transcript. Draws are keyed `(seed, date, key)`; the AI never consumes
`LeagueSeason.rng`.

## The ledger verb

```bash
godot --headless --path . --script res://tools/market_sim.gd -- ledger --currency EUR
```

It posts twelve monthly commercial and wage lines, a 40m fee over four years
and the end-of-season prize curve, then prints the opening envelope, the ledger
kinds and the tail as the club page reads it. Money stays in pounds; `--currency`
only changes the display.

## What a run builds

`LeagueSeason.create` from `data/pl_seed.sqlite`, then the market bootstrap
writes a contract per player and a finance row per league club. The seed itself
stays untouched; a run copies it into the save directory it names, so two runs
never share a file.

## The deal verb

```bash
godot --headless --path . --script res://tools/market_sim.gd -- deal \
  --from ESP-ALA1 --to ENG-ARS1 --fee 500000 --inject clearance
```

It proposes one permanent move on `--date` (default `2026-08-20`), runs the
validator pipeline and seals it in one transaction. `--inject` names the path to
prove: `none` signs, `list` refuses at the list check, `clearance` fails the
association wait, `fault` rolls back between the money and the contract, and
`registration` signs a player the buyer cannot register. The printed JSON is the
deal's own reading: state, reason, cash and headroom after the move.

## The youth verb

```bash
godot --headless --path . --script res://tools/market_sim.gd -- youth \
  --seasons 3 --clubs 20
```

It ages and retires the oldest, runs each club's intake, and prints intake and
retired counts plus a name sample. A fixed seed repeats the names.
