# Filing: container + sub-issues

After owner confirm + wiki gate + label mode.

## Split

| Situation | Action |
|-----------|--------|
| ≥2 independent workstreams (e.g. sim engine, UI, schema/wiki) | Container + one sub-issue per workstream |
| One shippable slice | Single issue via [`file-github-issue`](../../file-github-issue/SKILL.md); no empty container |
| Wiki-design still open for the whole theme | Prefer `question` on the set |

Sub-issue bodies: use file-github-issue [`feature-template.md`](../../file-github-issue/references/feature-template.md)
(or elucidate question template if that sub is design-only). Point each sub back
to the container theme in Summary. Keep acceptance scoped to that workstream.

Container body: [`container-template.md`](container-template.md).

## Create order

1. Create **container** with `gh issue create` (labels per mode).
2. Create each **sub-issue** with `gh issue create`.
3. Link each child with GraphQL `addSubIssue` (node IDs, not numbers).

```bash
REPO_OWNER=waigore
REPO_NAME=footballsim
PARENT_NUM=<container number>
CHILD_NUM=<sub-issue number>

PARENT_ID=$(gh api graphql -f query='
  query($o:String!,$n:String!,$num:Int!) {
    repository(owner:$o,name:$n){ issue(number:$num){ id } }
  }' -f o="$REPO_OWNER" -f n="$REPO_NAME" -F num="$PARENT_NUM" \
  --jq '.data.repository.issue.id')

CHILD_ID=$(gh api graphql -f query='
  query($o:String!,$n:String!,$num:Int!) {
    repository(owner:$o,name:$n){ issue(number:$num){ id } }
  }' -f o="$REPO_OWNER" -f n="$REPO_NAME" -F num="$CHILD_NUM" \
  --jq '.data.repository.issue.id')

gh api graphql -f query='
  mutation($parent:ID!,$child:ID!) {
    addSubIssue(input:{ issueId:$parent, subIssueId:$child }) {
      issue { number }
      subIssue { number }
    }
  }' -f parent="$PARENT_ID" -f child="$CHILD_ID"
```

Repeat for each child. If `addSubIssue` fails, leave explicit “Parent: #N” /
“Sub-issues: #…” links in the bodies and tell the owner linking failed.

## file-github-issue reuse

- Duplicate search and wiki-gate wording already done in capture-requirements.
- Do **not** re-run file-github-issue’s “no draft confirm” rule—owner already
  confirmed the pack.
- Do **not** invent extra labels. Leave assignee/milestone unset.
- Reply with container URL + every sub-issue URL.
