---
to: "docs/semantic-jira/a2a/agent-card.json"
mode: file
---
{
  "authority": "NONE",
  "generator": "ggen_igniter:semantic-jira-pack@26.9.19",
  "name": "semantic_jira_agent",
  "refusedSkills": [
    {
      "name": "publish_candidate",
      "reason": "REFUSED(forbidden-capability): Publish"
    },
    {
      "name": "push_candidate",
      "reason": "REFUSED(forbidden-capability): Push"
    },
    {
      "name": "run_exact_head_court",
      "reason": "UNSUPPORTED(generator-capability): external_do consequence cannot be manufactured by ash_a2a.install."
    }
  ],
  "skills": [
    {
      "consequence": "observe",
      "description": "Read admitted semantic work-order tasks without consequence.",
      "id": "SemanticJira.Work.Task.read",
      "name": "read",
      "semanticSkill": "observe_work_order"
    },
    {
      "consequence": "change",
      "description": "Record an exact-head court receipt against a work-order task; consequence-bearing, requires an authority grant.",
      "id": "SemanticJira.Work.Task.create",
      "name": "create",
      "semanticSkill": "record_court_receipt"
    }
  ],
  "stateMap": [
    {
      "reasonCode": "ALIVE_UNRECEIPTED",
      "receipted": "false",
      "standing": "ALIVE",
      "state": "working"
    },
    {
      "reasonCode": "ALIVE_RECEIPTED",
      "receipted": "true",
      "standing": "ALIVE",
      "state": "completed"
    },
    {
      "reasonCode": "BLOCKED",
      "receipted": "any",
      "standing": "BLOCKED",
      "state": "failed"
    },
    {
      "reasonCode": "BUILD_BROKEN",
      "receipted": "any",
      "standing": "BUILD_BROKEN",
      "state": "failed"
    },
    {
      "reasonCode": "PARTIAL_ALIVE",
      "receipted": "any",
      "standing": "PARTIAL_ALIVE",
      "state": "working"
    },
    {
      "reasonCode": "REFUSED",
      "receipted": "any",
      "standing": "REFUSED",
      "state": "rejected"
    },
    {
      "reasonCode": "UNKNOWN",
      "receipted": "any",
      "standing": "UNKNOWN",
      "state": "submitted"
    },
    {
      "reasonCode": "UNSUPPORTED",
      "receipted": "any",
      "standing": "UNSUPPORTED",
      "state": "rejected"
    }
  ]
}
