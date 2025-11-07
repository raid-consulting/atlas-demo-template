# Codex Issue Lifecycle

| Stage | Description | Human Responsibilities | Atlas Responsibilities | Codex Responsibilities |
| --- | --- | --- | --- | --- |
| Backlog | Intake queue awaiting Atlas refinement. | Capture high-level goal and context. | Identify missing details, surface implicit assumptions, and request clarifications. | None. |
| Refinement | Atlas prepares machine-verifiable work. | Respond to Atlas questions and provide resources. | Finalize explicit acceptance criteria, environment, and codex_prompt. | None. |
| Ready / In Progress | Work package is ready; execution occurs. | Manually trigger Codex and monitor progress. | Supply the codex_prompt and context, then support iteration as needed. | Generate implementation per the codex_prompt when triggered manually. |
| Review | Atlas validates results against criteria. | Provide additional context if Atlas flags gaps. | Verify acceptance criteria objectively and request fixes if unmet. | Address follow-up prompts if re-triggered manually. |
| Done | Verified work is complete. | Communicate completion to stakeholders. | Confirm closure and update project state. | None. |

## Operating Principles

- Codex triggering remains a manual action performed by a Human.
- During refinement, Atlas converts implicit expectations into explicit, testable statements to enable automated verification.
