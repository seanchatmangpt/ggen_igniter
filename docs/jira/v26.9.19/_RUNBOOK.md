# v26.9.19 wave runbook — manufactured by calver-ticket-day-pack (public vocabularies)

Stage chain 守→柲→算→除→偽→延→実 per APS OperatorGlyph; pacing per APS SwarmPacingLaw.

HISTORY LAW: the ticket .md files beside this runbook ARE the session history.

1. PLAN (守): select OPEN tickets; one worktree per ticket; status -> IN_PROGRESS.
2. SATURATE (柲): dispatch to the measured concurrency max for the active tier,
   maintained by top-up — never burst. On rate refusal: drain, halve pace.
3. AGENT CONTRACT (算/除/偽): "You work ticket <path>. READ IT FIRST — it is
   your entire history. Gates must exit 0. Commit atomically with receipt
   body. APPEND to History; set status DONE or BLOCKED. Never push."
4. RECEIPT (実): append the wave summary to _RUNLOG.md.
