---
name: clarify-github-issue
description: |-
  Chat with the Footballsim product owner to accept, revise, or reject one open
  GitHub issue labelled question (usually a design proposal from
  elucidate-design). On accept (as-written or with revisions): rewrite the issue
  body if needed, comment what changed, remove question, add todo plus bug or
  enhancement. On reject: close the issue right away. One issue per run. Use when
  the user asks to clarify a question issue, review a design proposal, accept or
  reject a wiki clarification, or run the clarify-github-issue skill.

  Examples:
    - no target → pick one open question; interview in chat; accept/reject
    - "#42" or "clarify #42" → that question issue only
    - "accept with these changes…" → rewrite body; todo + bug|enhancement
---

# Clarify GitHub issue (facade)

Canonical instructions: [`.agents/skills/clarify-github-issue/SKILL.md`](../../../.agents/skills/clarify-github-issue/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
