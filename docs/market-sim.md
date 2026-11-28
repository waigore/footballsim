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
| `register` | lists and permits | slots, homegrown, non-EU, U21, permit, freeze |
| `ffp` | the rolling three-year measure | the measure, the embargo, the deduction |

Each verb owns a file under `tools/market_sim/`; `tools/market_sim.gd` only
parses flags, loads the verb and prints its dictionary.

## The ai and ledger verbs

```bash
godot --headless --path . --script res://tools/market_sim.gd -- ai --clubs 172 --days 365
godot --headless --path . --script res://tools/market_sim.gd -- ledger --currency EUR
```

`ai` plays one season with the market AI on and prints the deal transcript;
`--mode every_day` must print the same transcript and exit `1` if a club is
stranded or no deal signed. `ledger` posts a season of commercial, wage,
amortisation and prize lines and prints the club's envelope and ledger tail.
Money stays in pounds; `--currency` only changes the display.

## What a run builds

`LeagueSeason.create` from `data/pl_seed.sqlite`. The seed stays untouched; a run
copies it into the save directory it names, so two runs never share a file.

## The deal verb

```bash
godot --headless --path . --script res://tools/market_sim.gd -- deal \
  --from ESP-ALA1 --to ENG-ARS1 --fee 500000 --inject clearance
```

One permanent move through the validator pipeline and one transaction.
`--inject` names the path: `none` signs, `list` refuses at the list check,
`clearance` fails the wait, `fault` rolls back, and `registration` signs a player
the buyer cannot register. The JSON is state, reason, cash and headroom.

## The register verb

```bash
godot --headless --path . --script res://tools/market_sim.gd -- register \
  --competition ucl --inject homegrown_min
```

Prints the club's list, then one verdict per rule — slots, under-21, homegrown,
non-EU, association-trained and permit — and proves one `--inject` path: `none`,
`list_full`, `homegrown_min`, `non_eu_cap`, `u21` or `permit`.

## The ffp verb

```bash
godot --headless --path . --script res://tools/market_sim.gd -- ffp --inject deduction
```

Three seasons of revenue, wages and amortisation, the rolling measure term by
term, and season-one monitoring. `--inject embargo` refuses an incoming
registration; `--inject deduction` books and applies the points once.

The sandbox is development tooling; a player reaches the same code through the
season and the club and player pages.
