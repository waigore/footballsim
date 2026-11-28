# Market sandbox

Run one market subsystem headless, against a scratch save built from the
shipped seed. The CLI prints; every rule lives in the verb's own module
([DR-20261128-31](https://github.com/waigore/footballsim/wiki/dr-20261128-31)).

## Commands

```bash
godot --headless --path . --script res://tools/market_sim.gd -- <verb> [flags]
```

Flags: `--seed`, `--clubs`, `--days`, `--expire`, `--seasons`, `--currency`,
`--from`, `--to`, `--player`, `--fee`, `--wage`, `--years`, `--date`, `--force`,
`--inject`. `--json`-style output is the printed JSON line. The run exits `1` on
a failed invariant or an injected failure.

## Verbs

| Verb | Runs | Proves |
|------|------|--------|
| `season` | settle, archive, rollover | archives, ageing, idempotence |
| `contracts` | expiry, renewal, options | the bootstrap envelope, free agency |
| `windows` | the association calendar | open and closed by date alone |
| `ledger` | revenue, wages, amortisation, prize | ledger kinds, currency display |
| `deal` | one permanent move through the engine | state machine, validators, commit and rollback |

Each verb owns a file under `tools/market_sim/`; `tools/market_sim.gd` only
parses flags, loads the verb and prints its dictionary.

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

The sandbox is development tooling. A player reaches the same code through the
season, the club page's finances block and the player page's contract and
TRANSFER blocks.
