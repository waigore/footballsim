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

Each verb owns a file under `tools/market_sim/`; `tools/market_sim.gd` only
parses flags, loads the verb and prints its dictionary.

## The ai verb

```bash
godot --headless --path . --script res://tools/market_sim.gd -- ai \
  --clubs 172 --days 365 --mode fixture_days
```

It plays a season with the market AI on and prints the deal transcript as one
JSON line: signed count, value spread, the refusal reasons and any club left
short of eleven. `--mode every_day` must print the same transcript — the
run exits `1` if a club is stranded or no deal signed. The AI never consumes
`LeagueSeason.rng`; every draw is keyed `(seed, "market", date, key)`.

## The ledger verb

```bash
godot --headless --path . --script res://tools/market_sim.gd -- ledger --currency EUR
```

It opens one save, posts twelve monthly commercial and wage lines, puts a 40m
fee on the books over four years, books the end-of-season prize curve and
prints the club's opening envelope, the kinds the ledger now holds and the
ledger tail as the club page would read it. Money stays in pounds; `--currency`
only changes the printed display.

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

The sandbox is development tooling. A player reaches the same code through the
season, the club page's finances block and the player page's contract block.
