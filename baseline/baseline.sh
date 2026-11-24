#!/usr/bin/env bash
# baseline.sh: apply the credential-lockbox org's repository baseline to one repo.
#
# Usage:
#   baseline/baseline.sh [--apply] [--check NAME]... credential-lockbox/<repo>
#
# Without --apply it is a dry run: it reads the repo and prints what it would
# change, and changes nothing. With --apply it makes those changes. Either way it
# reads the current state first and touches only what differs, so it is safe to
# re-run; a second --apply on an unchanged repo reports 0 changes.
#
# --check NAME (repeatable) is the only per-repo input: the status checks that
# must pass before a merge to main (GitHub Actions check names, e.g. ci-ok and
# "QA Gate"). With no --check, the main ruleset has no status-check rule.
#
# Run it as an organization owner (your own gh login). It refuses to run without
# admin on the repo. The org's GitHub Apps (the Dev and Muse bots) do not have
# Administration permission, by design: they can't change the rules that gate
# their own pull requests.
#
# WHAT IT MANAGES (everything else on the repo is left alone):
#
# 1. Ruleset "main" (rulesets/main.json), on the default branch:
#    - no deletion, no force push (non_fast_forward);
#    - pull request required: 1 approving review, stale reviews dismissed on
#      push, approval of the last push required (the pusher can't approve their
#      own push), extra approval for unattributed changes, code-owner review off,
#      thread resolution not required; merge, squash and rebase allowed;
#    - required status checks from --check (strict: branch must be up to date),
#      each pinned to the GitHub Actions app (integration id 15368);
#    - no bypass actors.
# 2. Ruleset "release tags" (rulesets/release-tags.json), on refs/tags/v* and
#    refs/tags/*-v*: no creation, update or deletion, except by the repository
#    admin role (bypass always). So release tags are created by a maintainer and
#    can't be moved or deleted afterward.
# 3. Repository settings (settings.json): issues on; squash, merge commit and
#    rebase merges allowed; auto-merge off; "update branch" button off;
#    head branches deleted on merge; squash commit title "commit or PR title"
#    and message "commit messages"; web commit sign-off not required.
#    Default branch main (skipped while the repo has no main branch).
# 4. Dependabot vulnerability alerts on.
# 5. Labels (labels.json): the fleet's workflow labels (Dev Active, Awaiting CI,
#    CI Failed, Ready for QA, QA Active, QA Failed, Ready for QA Signoff,
#    QA Approved, Muse Approved, Muse Failed) plus security, tracking and
#    accessibility. Missing labels are created, and color or description is
#    corrected. Labels not in the list are reported, never deleted.
#
# NOT MANAGED HERE: org-level settings (code security configuration, Actions
# defaults), wiki/projects/discussions toggles, collaborators and teams.
#
# Requires: gh (logged in as an org owner), jq.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ORG=credential-lockbox
ACTIONS_APP_ID=15368

usage() {
  sed -n '4,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

APPLY=0
REPO=
CHECKS=()
while (($#)); do
  case $1 in
    --apply) APPLY=1 ;;
    --check)
      [[ $# -ge 2 && -n $2 ]] || { echo "baseline: --check needs a check name" >&2; exit 2; }
      CHECKS+=("$2"); shift ;;
    -h|--help) usage ;;
    -*) echo "baseline: unknown option: $1" >&2; usage ;;
    *)
      [[ -z $REPO ]] || { echo "baseline: one repo at a time" >&2; exit 2; }
      REPO=$1 ;;
  esac
  shift
done
[[ -n $REPO ]] || usage
[[ $REPO == "$ORG"/* && $REPO != "$ORG/" && $REPO != */*/* ]] \
  || { echo "baseline: $REPO is not a $ORG repo (expected $ORG/<repo>)" >&2; exit 2; }

for tool in gh jq; do
  command -v "$tool" >/dev/null || { echo "baseline: $tool is required" >&2; exit 2; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Normalize JSON for comparison: sort arrays whose order GitHub doesn't keep.
NORM='walk(if type == "array" then
          (if all(.[]; type == "string") then sort
           elif all(.[]; type == "object" and has("type")) then sort_by(.type)
           elif all(.[]; type == "object" and has("context")) then sort_by(.context)
           elif all(.[]; type == "object" and has("actor_type")) then sort_by(.actor_type, .actor_id)
           else . end)
        else . end)'
# subset(a; b): every key in a is in b with an equal value (arrays: same length,
# element-wise subset). Extra keys GitHub adds on read don't count as a change.
# shellcheck disable=SC2016 # jq variables, not shell ones
SUBSET='def subset($a; $b):
  if ($a|type) == "object" then
    ($b|type) == "object" and all($a|to_entries[]; .key as $k | ($b|has($k)) and subset(.value; $b[$k]))
  elif ($a|type) == "array" then
    ($b|type) == "array" and ($a|length) == ($b|length)
    and all(range(0; $a|length); . as $i | subset($a[$i]; $b[$i]))
  else $a == $b end;'

CHANGES=0
change() { # change "<what>" <command...>
  local what=$1; shift
  CHANGES=$((CHANGES + 1))
  if ((APPLY)); then
    "$@" >/dev/null
    echo "  changed: $what"
  else
    echo "  would change: $what"
  fi
}
same() { echo "  ok: $1"; }

repo_json=$TMP/repo.json
gh api "repos/$REPO" >"$repo_json" \
  || { echo "baseline: can't read $REPO (does it exist, and is gh logged in?)" >&2; exit 1; }
if [[ $(jq -r '.permissions.admin // false' "$repo_json") != true ]]; then
  echo "baseline: your gh login has no admin on $REPO; run it as an org owner" >&2
  exit 1
fi

echo "$REPO ($([[ $APPLY == 1 ]] && echo apply || echo 'dry run'))"

# --- 1-2. Rulesets -----------------------------------------------------------
gh api --paginate "repos/$REPO/rulesets?includes_parents=false" --jq '.[] | {id, name}' \
  | jq -s . >"$TMP/rulesets.json"

desired_main=$TMP/ruleset-main.json
checks_json=$(printf '%s\n' "${CHECKS[@]+"${CHECKS[@]}"}" | jq -R . | jq -s 'map(select(length > 0))')
jq --argjson checks "$checks_json" --argjson app "$ACTIONS_APP_ID" '
  if ($checks | length) > 0 then
    .rules += [{type: "required_status_checks", parameters: {
      strict_required_status_checks_policy: true,
      do_not_enforce_on_create: false,
      required_status_checks: [$checks[] | {context: ., integration_id: $app}]}}]
  else . end' "$HERE/rulesets/main.json" >"$desired_main"

apply_ruleset() { # apply_ruleset <desired.json>
  local desired=$1 name id current
  name=$(jq -r .name "$desired")
  id=$(jq -r --arg n "$name" 'map(select(.name == $n)) | .[0].id // empty' "$TMP/rulesets.json")
  if [[ -z $id ]]; then
    change "create ruleset \"$name\"" gh api -X POST "repos/$REPO/rulesets" --input "$desired"
    return
  fi
  current=$TMP/current-$id.json
  gh api "repos/$REPO/rulesets/$id" >"$current"
  if jq -n -e --slurpfile d "$desired" --slurpfile c "$current" \
      "$SUBSET subset(\$d[0] | $NORM; \$c[0] | $NORM)" >/dev/null; then
    same "ruleset \"$name\""
  else
    diff <(jq -S "$NORM | {name, target, enforcement, conditions, bypass_actors, rules}" "$current") \
         <(jq -S "$NORM" "$desired") | sed 's/^/      /' || true
    change "update ruleset \"$name\" (id $id)" gh api -X PUT "repos/$REPO/rulesets/$id" --input "$desired"
  fi
}
echo "rulesets:"
apply_ruleset "$desired_main"
apply_ruleset "$HERE/rulesets/release-tags.json"

# --- 3. Settings -------------------------------------------------------------
echo "settings:"
patch=$TMP/settings-patch.json
jq -n --slurpfile d "$HERE/settings.json" --slurpfile c "$repo_json" '
  $d[0] | with_entries(select(.value != $c[0][.key]))' >"$patch"
default_branch=$(jq -r .default_branch "$repo_json")
if [[ $default_branch != main ]]; then
  if gh api "repos/$REPO/branches/main" >/dev/null 2>&1; then
    jq '. + {default_branch: "main"}' "$patch" >"$patch.new" && mv "$patch.new" "$patch"
  else
    echo "  skipped: default branch is \"$default_branch\" and there is no main branch yet"
  fi
fi
if [[ $(jq length "$patch") -gt 0 ]]; then
  jq -r --slurpfile c "$repo_json" 'to_entries[] | "      \(.key): \($c[0][.key] | tojson) -> \(.value | tojson)"' "$patch"
  change "repository settings ($(jq -r 'keys | join(", ")' "$patch"))" \
    gh api -X PATCH "repos/$REPO" --input "$patch"
else
  same "repository settings"
fi

# --- 4. Vulnerability alerts -------------------------------------------------
echo "vulnerability alerts:"
if gh api "repos/$REPO/vulnerability-alerts" >/dev/null 2>&1; then
  same "vulnerability alerts on"
else
  change "turn on vulnerability alerts" gh api -X PUT "repos/$REPO/vulnerability-alerts"
fi

# --- 5. Labels ---------------------------------------------------------------
echo "labels:"
gh api --paginate "repos/$REPO/labels?per_page=100" --jq '.[] | {name, color, description}' \
  | jq -s . >"$TMP/labels.json"
count=$(jq length "$HERE/labels.json")
for ((i = 0; i < count; i++)); do
  want=$(jq -c ".[$i]" "$HERE/labels.json")
  name=$(jq -r .name <<<"$want")
  have=$(jq -c --arg n "$name" 'map(select(.name == $n)) | .[0] // empty' "$TMP/labels.json")
  if [[ -z $have ]]; then
    change "create label \"$name\"" gh api -X POST "repos/$REPO/labels" \
      -f name="$name" -f color="$(jq -r .color <<<"$want")" -f description="$(jq -r .description <<<"$want")"
  elif jq -n -e --argjson w "$want" --argjson h "$have" \
      '($w.color | ascii_downcase) == ($h.color | ascii_downcase) and $w.description == ($h.description // "")' >/dev/null; then
    same "label \"$name\""
  else
    change "update label \"$name\" (color/description)" gh api -X PATCH \
      "repos/$REPO/labels/$(jq -rn --arg n "$name" '$n | @uri')" \
      -f color="$(jq -r .color <<<"$want")" -f description="$(jq -r .description <<<"$want")"
  fi
done
jq -r --slurpfile w "$HERE/labels.json" '
  ($w[0] | map(.name)) as $names | .[] | select(.name as $n | $names | index($n) | not) | .name' \
  "$TMP/labels.json" | while IFS= read -r extra; do
  echo "  left alone (not in the baseline): \"$extra\""
done

# --- Summary -----------------------------------------------------------------
if ((APPLY)); then
  echo "$REPO: $CHANGES change(s) applied"
else
  echo "$REPO: $CHANGES change(s) to make; dry run, nothing changed (re-run with --apply)"
fi
