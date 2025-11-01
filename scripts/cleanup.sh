#!/usr/bin/env bash
# scripts/cleanup.sh
# Remove the demo repo and the copied project created by bootstrap.sh

set -euo pipefail

OWNER="${OWNER:-raid-consulting}"

die(){ echo "error: $*" >&2; exit 1; }
log(){ echo "==> $*"; }
dbg(){ [ "${DEBUG:-0}" = "1" ] && echo "[debug] $*" >&2 || true; }

usage(){
  cat >&2 <<EOF
Usage: $0 <repo-name> [project-number-or-url]

Examples:
  $0 test-demo-18
  $0 test-demo-18 21
  $0 test-demo-18 https://github.com/orgs/${OWNER}/projects/21

ENV:
  OWNER=${OWNER}
EOF
  exit 1
}

extract_project_number(){
  local in="${1:-}"
  if [[ -z "$in" ]]; then echo ""; return 0; fi
  if [[ "$in" =~ /projects/([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$in" =~ ^[0-9]+$ ]]; then
    echo "$in"
  else
    die "second arg must be a project number or .../projects/<number> (got: $in)"
  fi
}

find_project_number_by_title_cli(){
  local title="$1"
  local raw norm
  raw="$(gh project list --owner "${OWNER}" --format json 2>/dev/null || echo '{}')"
  dbg "project list raw: $raw"
  norm="$(jq -c 'if type=="array" then . else (.projects // .items // []) end' <<<"$raw" 2>/dev/null || echo '[]')"
  dbg "project list normalized: $norm"
  jq -r --arg t "$title" '
    ( . // [] )
    | map(select(.title == $t))
    | sort_by(.number)
    | if length>0 then .[-1].number else empty end
  ' <<<"$norm"
}

find_project_number_by_title_graphql(){
  local title="$1"
  local q='
    query($org:String!){
      organization(login:$org){
        projectsV2(first:100){
          nodes{ title number }
        }
      }
    }'
  gh api graphql -f query="$q" -f org="${OWNER}" \
    --jq "(.data.organization.projectsV2.nodes // []) | map(select(.title==\"$title\")) | sort_by(.number) | if length>0 then .[-1].number else empty end" \
    2>/dev/null || true
}

find_project_number_by_title(){
  local title="$1"
  local n
  n="$(find_project_number_by_title_cli "$title" | tr -d '\n')"
  if [[ -z "$n" ]]; then
    n="$(find_project_number_by_title_graphql "$title" | tr -d '\n')"
  fi
  echo "$n"
}

delete_project(){
  local number="$1"
  if [[ -z "$number" ]]; then
    log "No project number resolved; skipping project delete."
    return 0
  fi
  log "Deleting project #${number} (owner ${OWNER})"
  if ! gh project delete "${number}" --owner "${OWNER}"; then
    log "Project delete failed or permission missing."
  fi
}

delete_repo(){
  local repo="$1"
  log "Deleting repo ${OWNER}/${repo}"
  if ! gh repo delete "${OWNER}/${repo}" --yes; then
    cat >&2 <<'TIP'
Tip:
- You must be an admin on the repository.
- Your GitHub CLI token must include the "delete_repo" scope:
    gh auth refresh -h github.com -s delete_repo
TIP
    log "Repo delete failed or already gone."
  fi
}

main(){
  local repo="${1:-}"; [[ -n "$repo" ]] || usage
  local proj_arg="${2:-}"

  # Must match bootstrap’s title (en dash U+2013):
  local title="Demo Project – ${repo}"

  local proj_num=""
  if [[ -n "$proj_arg" ]]; then
    proj_num="$(extract_project_number "$proj_arg")"
  else
    log "Resolving project by title: ${title}"
    proj_num="$(find_project_number_by_title "${title}")" || true
  fi

  if [[ -n "$proj_num" ]]; then
    log "Resolved project number: ${proj_num}"
  else
    log "Project not found by title. Proceeding with repo deletion only."
  fi

  delete_project "${proj_num}"
  delete_repo "${repo}"
  log "Cleanup complete."
}

main "$@"
