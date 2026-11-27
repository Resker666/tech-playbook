#!/usr/bin/env bash
# Preview by default. Never modify existing rulesets or branch protection.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash apply-rulesets.sh [--apply] [--include-private] --all-public
  bash apply-rulesets.sh [--apply] [--include-private] OWNER/REPO [OWNER/REPO ...]
--all-public       All owned public repositories (non-fork, non-archived).
--include-private  Allow explicitly named private repositories only.
--apply            Actually create rulesets; default is read-only preview.
EOF
}
apply=0
private=0
all=0
repos=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    --include-private) private=1 ;;
    --all-public) all=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) repos+=("$1") ;;
  esac
  shift
done
if [ "$all" -eq 1 ] && [ "${#repos[@]}" -ne 0 ]; then usage >&2; exit 2; fi
if [ "$all" -eq 0 ] && [ "${#repos[@]}" -eq 0 ]; then usage >&2; exit 2; fi
for cmd in gh jq; do
  command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 2; }
done
dir="$(cd -- "$(dirname -- "$0")" && pwd)"
template="$dir/protect-default-branch.json"
jq -e '.target == "branch" and .enforcement == "active" and .conditions.ref_name.include == ["~DEFAULT_BRANCH"]' "$template" >/dev/null
api() { gh api --hostname github.com -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }
owner="$(api user --jq .login)"
[ -n "$owner" ] || exit 2
if [ "$all" -eq 1 ]; then
  names="$(api --paginate 'user/repos?affiliation=owner&per_page=100' --jq '.[] | select(.private == false and .archived == false and .fork == false and .permissions.admin == true) | .full_name')"
  while IFS= read -r name; do
    [ -z "$name" ] || repos+=("$name")
  done <<< "$names"
fi
printf 'Account: %s | apply=%s | candidates=%s\n' "$owner" "$apply" "${#repos[@]}"
created=0; skipped=0; failed=0; planned=0
for repo in "${repos[@]}"; do
  if [[ ! "$repo" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "FAIL $repo: invalid repository name"; failed=$((failed+1)); continue
  fi
  if ! meta="$(api "repos/$repo")"; then
    echo "FAIL $repo: cannot read repository"; failed=$((failed+1)); continue
  fi
  if ! jq -e --arg owner "$owner" '.owner.login == $owner and .permissions.admin == true and .archived == false and .fork == false' <<< "$meta" >/dev/null; then
    echo "SKIP $repo: not owned/admin, fork or archived"; skipped=$((skipped+1)); continue
  fi
  if [ "$private" -eq 0 ] && jq -e '.private == true' <<< "$meta" >/dev/null; then
    echo "SKIP $repo: private (requires --include-private and eligible plan)"; skipped=$((skipped+1)); continue
  fi
  branch="$(jq -er '.default_branch | select(length > 0)' <<< "$meta")" || { echo "FAIL $repo: no default branch"; failed=$((failed+1)); continue; }
  encoded="$(jq -rn --arg b "$branch" '$b|@uri')"
  if ! info="$(api "repos/$repo/branches/$encoded")"; then
    echo "FAIL $repo: cannot read default branch (possibly empty)"; failed=$((failed+1)); continue
  fi
  if ! jq -e '.protected == false' <<< "$info" >/dev/null; then
    echo "SKIP $repo: default branch already protected or unknown"; skipped=$((skipped+1)); continue
  fi
  if ! rules="$(api "repos/$repo/rulesets?includes_parents=true&per_page=100")"; then
    echo "FAIL $repo: cannot inspect existing rulesets"; failed=$((failed+1)); continue
  fi
  if ! jq -e 'type == "array" and length == 0' <<< "$rules" >/dev/null; then
    echo "SKIP $repo: existing ruleset(s) or unexpected response; inspect manually"; skipped=$((skipped+1)); continue
  fi
  if [ "$apply" -eq 0 ]; then
    echo "PLAN $repo ($branch): create Protect default branch"; planned=$((planned+1)); continue
  fi
  if result="$(api -X POST "repos/$repo/rulesets" --input "$template")"; then
    if verified="$(api "repos/$repo/branches/$encoded")" && jq -e '.protected == true' <<< "$verified" >/dev/null; then
      echo "OK $repo ($branch): ruleset $(jq -r .id <<< "$result"), protected=true"; created=$((created+1))
    else
      echo "FAIL $repo: POST succeeded but protection not verified; inspect before retry"; failed=$((failed+1))
    fi
  else
    echo "FAIL $repo: create rejected; check plan/token permissions"; failed=$((failed+1))
  fi
done
printf 'Summary: planned=%s created_verified=%s skipped=%s failed=%s\n' "$planned" "$created" "$skipped" "$failed"
[ "$failed" -eq 0 ]
