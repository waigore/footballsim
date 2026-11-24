# UX playtest wiki evidence

Screenshots (and short clips when needed) live in the **GitHub wiki**, not the game repo.

## Hierarchy

| Page | Wiki slug / file | Role |
|------|------------------|------|
| Home | [`Evidence`](https://github.com/waigore/footballsim/wiki/Evidence) · `Evidence.md` | Index |
| Per run | `evidence/ux-playtest-YYYYMMDD` · `evidence/ux-playtest-YYYYMMDD.md` | One daily playtest report |

Link each new run from the Evidence home table. Create `Evidence.md` if missing.

## Clone / push

```bash
OWNER=waigore
REPO=footballsim
WIKI_DIR=$(mktemp -d)/wiki
gh repo clone "$OWNER/$REPO.wiki" "$WIKI_DIR" -- --depth 20
# mkdir -p evidence/images; edit Evidence.md + evidence/ux-playtest-YYYYMMDD.md
cd "$WIKI_DIR"
git add -A
git commit -m "$(cat <<'EOF'
UX playtest evidence YYYY-MM-DD.

EOF
)"
git push origin HEAD
```

Do not force-push the wiki. On non-fast-forward: `git pull --rebase` and retry.

## Run page skeleton (`evidence/ux-playtest-YYYYMMDD.md`)

```markdown
# UX playtest — YYYY-MM-DD

- Platform: desktop Linux (or host OS)
- Commit / branch: <SHA or main @ date>
- Scope: league loop + ≥1 match to full time

## Findings

### F1 — <short title>
- Issue: https://github.com/waigore/footballsim/issues/N  (or “not filed — duplicate of #M”)
- Kind: bug | inconsistency | enhancement
- Screenshots:
  ![desc](images/ux-YYYYMMDD-f1-a.png)

### F2 — …
```

Store binaries under `evidence/images/` (e.g. `ux-YYYYMMDD-f1-a.png`). Prefer relative image links.

## Evidence home row

| Run | Page | Issues |
|-----|------|--------|
| YYYY-MM-DD | [evidence/ux-playtest-YYYYMMDD](evidence/ux-playtest-YYYYMMDD) | #N, #M |

## Rules

- Wiki is the home for visuals; each GitHub issue **links** the run page (and finding section when useful).
- One calendar day → one run page (update in place if the same day re-runs).
- Do not leave large binaries only in the game repo or only in issue comments.
