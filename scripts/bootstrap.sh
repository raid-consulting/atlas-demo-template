#!/usr/bin/env bash
# scripts/bootstrap.sh
# Create a PUBLIC demo repo from a template, copy the configured Project (board),
# ensure Stage field options exist, create labels, create a starter issue (using template if available),
# add it to the project, and set Stage=Backlog.

set -euo pipefail

# --- Configuration -----------------------------------------------------------
OWNER="${OWNER:-raid-consulting}"
TEMPLATE_REPO="${TEMPLATE_REPO:-${OWNER}/atlas-demo-template}"
KANBAN_TEMPLATE="${KANBAN_TEMPLATE:-https://github.com/orgs/raid-consulting/projects/18}"
VIS_FLAG="--public"

# Columns for Stage field (must match your template project)
STAGE_OPTS=("Backlog" "Refinement" "Ready" "In Progress" "Review" "Done")

# Standard labels
LABELS=(atlas feedback-requested ready wip needs-fix ci-failed passed-AC bug p0 p1 p2 tshirt-s tshirt-m tshirt-l)

ISSUE_URLS=()

# --- Utility ----------------------------------------------------------------
die(){ echo "error: $*" >&2; exit 1; }
log(){ echo "==> $*"; }
dbg(){ [ "${DEBUG:-0}" = "1" ] && echo "[debug] $*" >&2 || true; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

extract_project_number(){
  local in="$1"
  if [[ "$in" =~ /projects/([0-9]+)$ ]]; then echo "${BASH_REMATCH[1]}"
  elif [[ "$in" =~ ^[0-9]+$ ]]; then echo "$in"
  else die "KANBAN_TEMPLATE must be a number or .../projects/<number> (got: $in)"
  fi
}

# --- Core steps --------------------------------------------------------------
create_repo(){
  local repo="$1"
  log "Creating repo from template: ${TEMPLATE_REPO} → ${OWNER}/${repo}"
  gh repo create "${OWNER}/${repo}" --template "${TEMPLATE_REPO}" ${VIS_FLAG}
  log "Repo created: https://github.com/${OWNER}/${repo}"
}

create_or_copy_project(){
  local repo="$1" title pj
  title="Demo Project – ${repo}"
  local template_number
  template_number="$(extract_project_number "${KANBAN_TEMPLATE}")"

  log "Copying project template ${template_number} → ${title}"
  pj=$(gh project copy "${template_number}" \
        --source-owner "${OWNER}" \
        --target-owner "${OWNER}" \
        --title "${title}" \
        --format json)

  PROJECT_NUMBER=$(jq -r '.number' <<<"$pj")
  PROJECT_URL=$(jq -r '.url' <<<"$pj")
  PROJECT_ID=$(jq -r '.id'  <<<"$pj")
  log "Project copied: ${PROJECT_URL} (number ${PROJECT_NUMBER})"
  dbg "project id: ${PROJECT_ID}"
}

ensure_stage_field_and_options(){
  log "Ensuring Stage field exists with required options"
  local raw norm stage_json
  raw=$(gh project field-list "${PROJECT_NUMBER}" --owner "${OWNER}" --format json)
  norm=$(echo "$raw" | jq -c 'if type=="array" then . else (.fields // .items // []) end')
  stage_json=$(echo "$norm" | jq -c '[ .[] | select(.name=="Stage" and (.type|tostring|test("SingleSelect";"i"))) ] | first // empty')

  if [ -n "${stage_json}" ]; then
    STAGE_FIELD_ID=$(echo "$stage_json" | jq -r '.id')
    mapfile -t existing < <(echo "$stage_json" | jq -r '.options[]?.name' 2>/dev/null || true)
    for opt in "${STAGE_OPTS[@]}"; do
      if ! printf '%s\n' "${existing[@]:-}" | grep -Fxq -- "$opt"; then
        gh project field-option-create \
          --project-id "${PROJECT_ID}" \
          --field-id "${STAGE_FIELD_ID}" \
          --name "${opt}" >/dev/null
      fi
    done
  else
    local args=(project field-create "${PROJECT_NUMBER}" --owner "${OWNER}" --name Stage --data-type SINGLE_SELECT --format json)
    for s in "${STAGE_OPTS[@]}"; do args+=(--single-select-options "$s"); done
    local fjson; fjson=$(gh "${args[@]}")
    STAGE_FIELD_ID=$(echo "$fjson" | jq -r '.id')
  fi

  # Re-fetch to identify Backlog option id
  raw=$(gh project field-list "${PROJECT_NUMBER}" --owner "${OWNER}" --format json)
  norm=$(echo "$raw" | jq -c 'if type=="array" then . else (.fields // .items // []) end')
  stage_json=$(echo "$norm" | jq -c '[ .[] | select(.name=="Stage" and (.type|tostring|test("SingleSelect";"i"))) ] | first // empty')
  STAGE_BACKLOG_ID=$(echo "$stage_json" | jq -r '.options[]? | select(.name=="Backlog") | .id' || true)
  [ -n "${STAGE_BACKLOG_ID:-}" ] || die "Template project must have Stage option 'Backlog'."
  dbg "Stage field id: ${STAGE_FIELD_ID} ; Backlog option id: ${STAGE_BACKLOG_ID}"
}

create_labels(){
  local repo="$1"
  log "Creating labels"
  for L in "${LABELS[@]}"; do
    gh label create "$L" --repo "${OWNER}/${repo}" -c "#0366d6" -d "" 2>/dev/null || true
  done
}

create_starter_issues(){
  local repo="$1"
  log "Creating starter demo issues"

  local atlas_instructions_codex atlas_instructions_ops
  atlas_instructions_codex=$(cat <<'EOF'
<details>
<summary>Atlas Instructions</summary>

```
ATLAS:REFINE
PURPOSE: Prepare this issue for execution by OpenAI Codex.
OUTPUTS:
  - codex_prompt
  - acceptance_criteria
  - environment
COMPLETE WHEN:
  - codex_prompt, acceptance_criteria, and environment are present and consistent.
STATE:
  COMPLETE:
    MOVE: Ready
    ADD: [ready, atlas-prepared]
    REMOVE: [atlas, feedback-requested]
  INCOMPLETE:
    MOVE: Backlog
    ADD: [feedback-requested]
REVIEW:
  PASS:
    MOVE: Done
  FAIL:
    MOVE: Ready
    ADD: [needs-fix]
NOTES:
  - Atlas refines and generates the codex_prompt after acceptance criteria are complete.
  - Acceptance criteria must be fully explicit for Atlas to verify.
  - Human triggers Codex manually once issue is Ready.
  - Atlas verifies output during Review.
```

</details>
EOF
)

  atlas_instructions_ops=$(cat <<'EOF'
<details>
<summary>Atlas Instructions</summary>

```
ATLAS:REFINE
PURPOSE: Prepare this issue for verification or procedural execution (non-Codex).
OUTPUTS:
  - acceptance_criteria
  - environment
COMPLETE WHEN:
  - Acceptance criteria are defined and verifiable.
STATE:
  COMPLETE:
    MOVE: Ready
    ADD: [ready, atlas-prepared]
    REMOVE: [atlas, feedback-requested]
  INCOMPLETE:
    MOVE: Backlog
    ADD: [feedback-requested]
REVIEW:
  PASS:
    MOVE: Done
  FAIL:
    MOVE: Ready
    ADD: [needs-fix]
NOTES:
  - Use "refine" for Backlog→Ready.
  - This issue type does not produce a Codex prompt.
```

</details>
EOF
)

  local initial_body
  initial_body=$(cat <<'EOF'
## Goal
Deliver an `index.html` landing page that welcomes visitors and demonstrates the Atlas loop end-to-end.

## Acceptance Criteria
- [ ] AC-1: Visiting the GitHub Pages URL loads the new `index.html` landing page with simple, elegant styling and welcoming copy.
- [ ] AC-2: The landing page renders without console errors in the browser.

## Environment
- repo: .
- language: Static site (HTML/CSS)
- commands: n/a
EOF
)

  local github_pages_body
  github_pages_body=$(cat <<'EOF'
## Goal
Enable GitHub Pages so reviewers can access the landing page served from the default branch.

## Acceptance Criteria
- [ ] AC-1: GitHub Pages is configured for the repository, serving the site from the default branch so reviewers can access it.

## Environment
- repo: .
- language: Settings-only change
- commands: n/a
EOF
)

  local issue_one_body issue_two_body
  issue_one_body=$(printf '%s\n\n%s\n' "$initial_body" "$atlas_instructions_codex")
  issue_two_body=$(printf '%s\n\n%s\n' "$github_pages_body" "$atlas_instructions_ops")

  local first_issue_url second_issue_url
  first_issue_url=$(gh api -X POST "repos/${OWNER}/${repo}/issues" \
    -f title="Demo – create initial landing page" \
    -f body="$issue_one_body" \
    -f labels[]=atlas \
    -f labels[]=p2 \
    -f labels[]=tshirt-s \
    --jq '.html_url')
  log "Issue created (landing page): ${first_issue_url}"

  second_issue_url=$(gh api -X POST "repos/${OWNER}/${repo}/issues" \
    -f title="Configure GitHub Pages for landing page" \
    -f body="$issue_two_body" \
    -f labels[]=atlas \
    -f labels[]=p2 \
    -f labels[]=tshirt-s \
    --jq '.html_url')
  log "Issue created (GitHub Pages): ${second_issue_url}"

  ISSUE_URLS=("$first_issue_url" "$second_issue_url")
}

add_issue_to_project_and_stage(){
  local issue_url="$1"
  log "Linking issue to project: ${issue_url}"
  local item_json item_id
  item_json=$(gh project item-add "${PROJECT_NUMBER}" --owner "${OWNER}" --url "${issue_url}" --format json)
  item_id=$(echo "$item_json" | jq -r '.id')
  dbg "item id: $item_id"

  log "Setting Stage=Backlog"
  gh project item-edit \
    --id "${item_id}" \
    --project-id "${PROJECT_ID}" \
    --field-id "${STAGE_FIELD_ID}" \
    --single-select-option-id "${STAGE_BACKLOG_ID}" >/dev/null 2>&1 || true
}

print_summary(){
  local repo="$1"
  echo
  echo "Repo: https://github.com/${OWNER}/${repo}"
  echo "Project: ${PROJECT_URL}"
  local issue
  for issue in "${ISSUE_URLS[@]}"; do
    echo "Issue: ${issue}"
  done
}

# --- Main -------------------------------------------------------------------
main(){
  need gh
  need jq
  local repo="${1:-}"
  [ -n "${repo}" ] || die "usage: $0 <new-repo-name>"

  create_repo "${repo}"
  create_or_copy_project "${repo}"
  ensure_stage_field_and_options
  create_labels "${repo}"
  create_starter_issues "${repo}"
  local issue_url
  for issue_url in "${ISSUE_URLS[@]}"; do
    add_issue_to_project_and_stage "${issue_url}"
  done
  print_summary "${repo}"
}

main "$@"
