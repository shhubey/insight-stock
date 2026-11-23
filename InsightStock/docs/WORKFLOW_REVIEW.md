# Review of the supplied n8n exports

Review date: 22 November 2026. Scope: both JSON exports supplied by the project owner. This was a configuration review; it did not execute n8n, send a Telegram message, inspect the deployed database schema, or retrieve production execution logs.

| Check | Observed in original exports | Assessment |
| --- | --- | --- |
| Activation | Both exports have `active: true` | Exported active state confirmed; scheduled execution success still needs an execution record |
| Follow-up flow | Schedule → GET manager_decisions → POST decision_followups | Connected in the expected order |
| Task deduplication | POST uses `on_conflict=decision_id` and `Prefer: resolution=ignore-duplicates,return=representation` | Correct request for a database primary/unique key on decision_id; the migration supplies that key |
| Field mapping | Decision ID, source product/SKU, action, note, responsibility, assessment risk | Mappings point to the expected server-saved decision fields |
| Pending notifications | GET filters `notified_at=is.null` | Acknowledged tasks are excluded on a later read |
| Send before acknowledgment | GET pending → Telegram → PATCH | Failed send does not acknowledge when node errors stop the flow |
| Item identity | PATCH uses `$('Get pending alerts').item.json.decision_id` | Uses the paired original task after Telegram replaces the current item data |
| Ack filter | PATCH also filters `notified_at=is.null` | Avoids overwriting an already-set timestamp; it does not prevent duplicate sends |
| Text | HTML mode; ampersand escaped before angle brackets | Product, note and role text are escaped for the selected parse mode |
| Schedule | Hour rules; Telegram minute 5; decision minute omitted | Declared node defaults are one hour/minute zero; instance timezone applies in the original files |
| Error behavior | No continue-on-error override in the supplied nodes | Default stop behavior; portable copies make it explicit |
| Credentials | Credential references, no embedded Supabase secret or bot token detected | References and personal Chat ID removed from portable copies |
| Recorded execution data | pinData empty in both exports | No pinned decision/session data to remove |

## Changes only in the portable copies

The owner's live workflows have not been modified. The package contains inactive import templates. Credential IDs/names, instance/workflow metadata, the Telegram webhook ID and personal Chat ID were removed. Project URLs use a placeholder. Node IDs and expression-referenced node names are preserved. One-hour intervals, minute 0/5, JSON request bodies and stop-on-error are explicit. Template timezone is Asia/Seoul; choose the same appropriate timezone in both imported workflows.

## Reliability boundaries

- Task creation is repeatable through the decision_id database key. This does not imply exactly-once Telegram delivery.
- If Telegram accepts a message but the following PATCH fails, the next run can send it again. An ambiguous send timeout has the same risk.
- Two overlapping alert executions can both read the same pending row and send it. No database claim/lease or delivery idempotency key is implemented. Run one alerts workflow and avoid overlapping manual runs.
- There is no per-item dead-letter handling. One repeatedly failing message may delay the remaining pending batch. n8n execution logs provide the current error record; there is no separate custom error table/workflow.
- Every saved decision produces a follow-up, including monitoring and “No action yet”; these are notifications of recorded decisions, not urgent-only alerts. `status` remains NEW; there is no task-completion UI.
- Both GETs read an unpaginated API response. This is suitable for the nine-row demonstration, not a large history that can exceed the server response limit.
- Five-minute staggering is a schedule choice, not a dependency or delivery-time guarantee. A late task can wait for the next alert cycle.
- RLS isolation, deployed constraints, live multi-item pairing, Telegram failures and automatic scheduled runs have not been independently exercised in this review.

## Sources

- https://docs.n8n.io/workflows/export-import/
- https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.scheduletrigger/
- https://github.com/n8n-io/n8n/blob/master/packages/nodes-base/nodes/Schedule/ScheduleTrigger.node.ts
- https://docs.n8n.io/data/data-mapping/data-item-linking/item-linking-errors/
- https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.telegram/message-operations/
