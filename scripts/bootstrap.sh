#!/usr/bin/env bash
# scripts/bootstrap.sh
# Create a PUBLIC demo repo from a template repo, copy a preconfigured Project (board),
# ensure Stage field options exist, create labels, create starter issue, add to project, set Stage=Backlog.

set -euo pipefail

# --- Config (override via env) ---
OWNER="${OWNER:-raid-consulting}"
TEMPLATE_REPO="${TEMPLATE_REPO:-${OWNER}/atlas-demo-template}"
VIS_FLAG="--public"

# Accept either a full URL like ".../projects/18" or just "18"
KANBAN_TEMPLATE="${KANBAN_TEMPLATE:-https://github.com/orgs/raid-consulting/projects/18}"

# Your workflow stages (columns)
STAGE_OPTS=("Backlog" "Refinement" "Ready" "In Progress" "Review" "Done")

# Standard labels
LABELS=(atlas feedback-requested ready wip needs-fix ci-failed passed-AC bug p0 p1 p2 tshirt-s tshirt-m tshirt-l)

die(){ echo "error: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
log(){ echo "==> $*"; }
dbg(){ [ "${DEBUG:-0}" = "1" ] && echo "[debug] $*" >&2 || true; }

extract_project_number(){
  # Input may be a number "18" or URL ".../projects/18"
  local in="$1"
  if [[ "$in" =~ /projects/([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$in" =~ ^[0-9]+$ ]]; then
    echo "$in"
  else
    die "KANBAN_TEMPLATE must be a number or .../projects/<number> (got: $in)"
  fi
}

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
  # Copy the template project inside the same org
  pj=$(gh project copy "${template_number}" \
        --source-owner "${OWNER}" \
        --target-owner "${OWNER}" \
        --title "${title}" \
        --format json)

  # Capture number/url/node id
  PROJECT_NUMBER=$(jq -r '.number' <<<"$pj")
  PROJECT_URL=$(jq -r '.url' <<<"$pj")
  PROJECT_ID=$(jq -r '.id'  <<<"$pj")
  log "Project copied: ${PROJECT_URL} (number ${PROJECT_NUMBER})"
  dbg "project id: ${PROJECT_ID}"
}

ensure_stage_field_and_options(){
  # Ensure Stage exists with the required options; capture Backlog option id
  log "Ensuring Stage field exists with required options"
  local raw norm stage_json
  raw=$(gh project field-list "${PROJECT_NUMBER}" --owner "${OWNER}" --format json)
  norm=$(echo "$raw" | jq -c 'if type=="array" then . else (.fields // .items // []) end')

  # Find Stage single-select
  stage_json=$(echo "$norm" | jq -c '[ .[] | select(.name=="Stage" and (.type|tostring|test("SingleSelect";"i"))) ] | first // empty')

  if [ -n "${stage_json}" ]; then
    STAGE_FIELD_ID=$(echo "$stage_json" | jq -r '.id')
    mapfile -t existing < <(echo "$stage_json" | jq -r '.options[]?.name' 2>/dev/null || true)
    # Add any missing options (using node-id based flag)
    for opt in "${STAGE_OPTS[@]}"; do
      if ! printf '%s\n' "${existing[@]:-}" | grep -Fxq -- "$opt"; then
        gh project field-option-create \
          --project-id "${PROJECT_ID}" \
          --field-id "${STAGE_FIELD_ID}" \
          --name "${opt}" >/dev/null
      fi
    done
  else
    # If the template somehow lacks Stage, create it with all options (owner+number path)
    local args=(project field-create "${PROJECT_NUMBER}" --owner "${OWNER}" --name Stage --data-type SINGLE_SELECT --format json)
    for s in "${STAGE_OPTS[@]}"; do args+=(--single-select-options "$s"); done
    local fjson; fjson=$(gh "${args[@]}")
    STAGE_FIELD_ID=$(echo "$fjson" | jq -r '.id')
  fi

  # Re-read to fetch option ids
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

create_starter_issue(){
  local repo="$1"
  log "Creating starter demo issue"
  local body
  body=$(cat <<'EOF'
Why
- Validate the loop end-to-end with a harmless change.

What
- Add "About" link in header pointing to /about.

Out of scope
- Styling beyond current nav pattern.
- About page content.

Draft ACs
- AC-1: Header shows "About" on desktop.
- AC-2: Clicking "About" opens /about.
- AC-3: No console errors on load.

Meta
- Priority: p2
- Size: tshirt-s
EOF
)
  ISSUE_URL=$(gh api -X POST "repos/${OWNER}/${repo}/issues" \
    -f title="Demo – add About link to header" \
    -f body="$body" \
    -f labels[]=atlas \
    -f labels[]=p2 \
    -f labels[]=tshirt-s \
    --jq '.html_url')
  log "Issue created: ${ISSUE_URL}"
}

add_issue_to_project_and_stage(){
  log "Linking issue to project"
  local item_json item_id
  item_json=$(gh project item-add "${PROJECT_NUMBER}" --owner "${OWNER}" --url "${ISSUE_URL}" --format json)
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
  echo "Issue: ${ISSUE_URL}"
}

main(){
  need gh
  need jq
  local repo="${1:-}"
  [ -n "${repo}" ] || die "usage: $0 <new-repo-name>"

  create_repo "${repo}"
  create_or_copy_project "${repo}"
  ensure_stage_field_and_options
  create_labels "${repo}"
  create_starter_issue "${repo}"
  add_issue_to_project_and_stage
  print_summary "${repo}"
}

main "$@"
