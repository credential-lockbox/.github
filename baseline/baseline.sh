#!/usr/bin/env bash
# baseline.sh: apply the credential-lockbox org's repository baseline to one repo.
#
# Usage:
#   baseline/baseline.sh [--apply] [--check NAME]... [--no-checks] [--empty-ok] credential-lockbox/<repo>
#
# Without --apply it is a dry run: it reads the repo and prints what it would
# change, and changes nothing. With --apply it makes those changes. Either way it
# reads the current state first and touches only what differs, so it is safe to
# re-run; a second --apply on an unchanged repo reports 0 changes.
#
# --check NAME (repeatable) is the only per-repo input: the status checks that
# must pass before a merge to main (GitHub Actions check names, e.g. ci-ok and
# "QA Gate"). Each must be a GitHub Actions job that runs on pull requests: a
# name nothing reports blocks every merge. Give the repo's full list every
# time. If you give none and the repo's main ruleset already requires checks,
# the script stops rather than remove them; --no-checks says you mean to run
# with no required checks.
#
# The main ruleset requires pull requests and blocks force pushes, so a repo
# gets it after its first history is on main. With no main branch yet, a dry
# run warns and --apply stops; --empty-ok applies anyway.
#
# If a change fails, the script prints FAILED with GitHub's reply, goes on with
# the rest, and exits 1 at the end. Any other API error stops it at once.
#
# Run it as an organization owner (your own gh login). It refuses to run without
# admin on the repo, and stops if the name now resolves to another repo (renamed
# or transferred): run it on the current name. The org's GitHub Apps (the Dev and Muse bots) do not have
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
#    admin role (bypass always). So release tags are created by a repository
#    admin and can't be moved or deleted afterward.
# 3. Repository settings (settings.json): issues on; squash, merge commit and
#    rebase merges allowed; auto-merge off; "update branch" button off;
#    head branches deleted on merge; squash commit title "commit or PR title"
#    and message "commit messages"; web commit sign-off not required.
#    Default branch main (skipped while the repo has no main branch).
# 4. Dependabot vulnerability alerts on, and private vulnerability reporting on
#    (the "Report a vulnerability" button, where private security reports go).
# 5. Labels (labels.json): the fleet's workflow labels (Dev Active, Awaiting CI,
#    CI Failed, Ready for QA, QA Active, QA Failed, Ready for QA Signoff,
#    QA Approved, Muse Approved, Muse Failed) plus security, tracking and
#    accessibility. Missing labels are created, and name case, color or
#    description is corrected (GitHub matches label names ignoring case).
#    Labels not in the list are reported, never deleted.
#
# NOT MANAGED HERE: org-level settings (code security configuration, Actions
# defaults), wiki/projects/discussions toggles, collaborators and teams.
#
# Requires: gh (logged in as an org owner), jq.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ORG=credential-lockbox
ACTIONS_APP_ID=15368

usage() { # usage <exit code>: --help prints the whole intro to stdout
  if (($1 == 0)); then
    sed -n '4,/^# Run it as/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
  else
    sed -n '4,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  fi
  exit "$1"
}
die() { echo "baseline: $*" >&2; exit 1; }

APPLY=0
NO_CHECKS=0
EMPTY_OK=0
REPO=
CHECKS=()
while (($#)); do
  case $1 in
    --apply) APPLY=1 ;;
    --no-checks) NO_CHECKS=1 ;;
    --empty-ok) EMPTY_OK=1 ;;
    --check)
      if [[ $# -lt 2 || $2 == -* || -z ${2//[[:space:]]/} || $2 == *$'\n'* \
            || $2 == [[:space:]]* || $2 == *[[:space:]] ]]; then
        echo "baseline: --check needs a check name, with no leading or trailing space or newline (got: '${2-}')" >&2
        exit 2
      fi
      CHECKS+=("$2"); shift ;;
    -h|--help) usage 0 ;;
    -*) echo "baseline: unknown option: $1" >&2; usage 2 ;;
    *)
      [[ -z $REPO ]] || { echo "baseline: one repo at a time" >&2; exit 2; }
      REPO=$1 ;;
  esac
  shift
done
[[ -n $REPO ]] || usage 2
name=${REPO#"$ORG"/}
if [[ $REPO != "$ORG"/* || ! $name =~ ^[A-Za-z0-9._-]+$ || $name == . || $name == .. ]]; then
  echo "baseline: $REPO is not a $ORG repo (expected $ORG/<repo>)" >&2; exit 2
fi
if ((NO_CHECKS)) && ((${#CHECKS[@]})); then
  echo "baseline: --no-checks and --check together" >&2; exit 2
fi

for tool in gh jq; do
  command -v "$tool" >/dev/null || { echo "baseline: $tool is required" >&2; exit 2; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# http_status <path>: the HTTP status of a GET, so "absent" (404) is told apart
# from any other error.
http_status() {
  { gh api -i "$1" 2>/dev/null || true; } | awk 'NR == 1 { print $2; exit }'
}

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
# The contexts a ruleset requires, one per line.
CONTEXTS='[.rules[]? | select(.type == "required_status_checks")
          | .parameters.required_status_checks[].context] | sort | .[]'
# Live checks reported by an app other than GitHub Actions: "<context> (app <id>)".
# shellcheck disable=SC2016 # jq variables, not shell ones
OTHER_APPS='[.rules[]? | select(.type == "required_status_checks")
            | .parameters.required_status_checks[]
            | select((.integration_id // 0) != $app)
            | "\(.context) (app \(.integration_id // "any"))"] | sort | .[]'

CHANGES=0
FAILED=0
change() { # change "<what>" <command...>
  local what=$1; shift
  CHANGES=$((CHANGES + 1))
  if ((!APPLY)); then
    echo "  would change: $what"
  elif "$@" >"$TMP/out" 2>&1; then
    echo "  changed: $what"
  else
    FAILED=$((FAILED + 1))
    echo "  FAILED: $what"
    sed 's/^/      /' "$TMP/out"
  fi
}
same() { echo "  ok: $1"; }

repo_json=$TMP/repo.json
gh api "repos/$REPO" >"$repo_json" 2>"$TMP/err" \
  || die "can't read $REPO: $(cat "$TMP/err") (does it exist, and is gh logged in?)"
# GitHub answers a renamed or transferred repo's old name with a redirect, and
# gh follows it: refuse if the name already resolves to another repo when the
# run starts. (A repo moved during the run isn't caught; moving one needs admin.)
jq -e '(.full_name | type) == "string"' "$repo_json" >/dev/null 2>&1 \
  || die "unexpected reply from GET repos/$REPO (no full_name)"
jq -e --arg r "$REPO" '(.full_name | ascii_downcase) == ($r | ascii_downcase)' "$repo_json" >/dev/null \
  || die "$REPO now resolves to $(jq -r .full_name "$repo_json") (renamed or transferred); run it on the current name"
[[ $(jq -r '.permissions.admin // false' "$repo_json") == true ]] \
  || die "your gh login has no admin on $REPO; run it as an org owner"

echo "$REPO ($([[ $APPLY == 1 ]] && echo apply || echo 'dry run'))"

main_status=$(http_status "repos/$REPO/branches/main")
case $main_status in
  200) ;;
  404)
    if ((APPLY && !EMPTY_OK)); then
      die "$REPO has no main branch yet. Push its first history to main, then run this (the main ruleset requires pull requests and blocks force pushes), or pass --empty-ok"
    fi
    echo "  WARNING: $REPO has no main branch yet; push its first history before applying (or pass --empty-ok)" ;;
  *) die "can't tell whether $REPO has a main branch (GET branches/main: HTTP ${main_status:-no reply})" ;;
esac

# --- 1-2. Rulesets -----------------------------------------------------------
gh api --paginate "repos/$REPO/rulesets?includes_parents=false" --jq '.[] | {id, name}' \
  | jq -s . >"$TMP/rulesets.json"

ruleset_id() { jq -r --arg n "$1" 'map(select(.name == $n)) | .[0].id // empty' "$TMP/rulesets.json"; }

main_id=$(ruleset_id main)
live_contexts=
if [[ -n $main_id ]]; then
  gh api "repos/$REPO/rulesets/$main_id" >"$TMP/current-$main_id.json"
  live_contexts=$(jq -r "$CONTEXTS" "$TMP/current-$main_id.json")
fi
if ((${#CHECKS[@]} == 0 && !NO_CHECKS)) && [[ -n $live_contexts ]]; then
  echo "baseline: the main ruleset on $REPO requires these checks:" >&2
  while IFS= read -r c; do echo "  $c"; done <<<"$live_contexts" >&2
  echo "Give them again with --check (one each), or pass --no-checks to remove them." >&2
  other=$(jq -r --argjson app "$ACTIONS_APP_ID" "$OTHER_APPS" "$TMP/current-$main_id.json")
  if [[ -n $other ]]; then
    echo "Note: --check pins each check to GitHub Actions, and these come from another app:" >&2
    while IFS= read -r c; do echo "  $c"; done <<<"$other" >&2
  fi
  exit 2
fi

desired_main=$TMP/ruleset-main.json
checks_json=$(printf '%s\n' "${CHECKS[@]+"${CHECKS[@]}"}" | jq -R . | jq -s 'map(select(length > 0)) | unique')
jq --argjson checks "$checks_json" --argjson app "$ACTIONS_APP_ID" '
  if ($checks | length) > 0 then
    .rules += [{type: "required_status_checks", parameters: {
      strict_required_status_checks_policy: true,
      do_not_enforce_on_create: false,
      required_status_checks: [$checks[] | {context: ., integration_id: $app}]}}]
  else . end' "$HERE/rulesets/main.json" >"$desired_main"

show_contexts() { # show_contexts <live file or empty> <desired file>
  local live=$1 desired=$2
  local want have
  want=$(jq -r "$CONTEXTS" "$desired")
  have=
  [[ -z $live ]] || have=$(jq -r "$CONTEXTS" "$live")
  [[ -z $live ]] || jq -r --argjson app "$ACTIONS_APP_ID" "$OTHER_APPS" "$live" \
    | sed 's/^/      required check source changes to GitHub Actions: /'
  [[ $want != "$have" ]] || return 0
  comm -13 <(sort <<<"$have") <(sort <<<"$want") | sed '/^$/d; s/^/      required check added: /'
  comm -23 <(sort <<<"$have") <(sort <<<"$want") | sed '/^$/d; s/^/      required check REMOVED: /'
}

apply_ruleset() { # apply_ruleset <desired.json>
  local desired=$1 name id current
  name=$(jq -r .name "$desired")
  id=$(ruleset_id "$name")
  if [[ -z $id ]]; then
    show_contexts "" "$desired"
    change "create ruleset \"$name\"" gh api -X POST "repos/$REPO/rulesets" --input "$desired"
    return
  fi
  current=$TMP/current-$id.json
  [[ -s $current ]] || gh api "repos/$REPO/rulesets/$id" >"$current"
  # An empty bypass list may be left out of the reply.
  jq '.bypass_actors //= []' "$current" >"$current.n" && mv "$current.n" "$current"
  if jq -n -e --slurpfile d "$desired" --slurpfile c "$current" \
      "$SUBSET subset(\$d[0] | $NORM; \$c[0] | $NORM)" >/dev/null; then
    same "ruleset \"$name\""
  else
    show_contexts "$current" "$desired"
    diff -u --label "live" --label "baseline" \
      <(jq -S "$NORM | {name, target, enforcement, conditions, bypass_actors, rules}" "$current") \
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
  if [[ $main_status == 200 ]]; then
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
alerts_status=$(http_status "repos/$REPO/vulnerability-alerts")
case $alerts_status in
  204) same "vulnerability alerts on" ;;
  404) change "turn on vulnerability alerts" gh api -X PUT "repos/$REPO/vulnerability-alerts" ;;
  *) die "can't read vulnerability alerts on $REPO (GET vulnerability-alerts: HTTP ${alerts_status:-no reply})" ;;
esac

echo "private vulnerability reporting:"
pvr=$(gh api "repos/$REPO/private-vulnerability-reporting" --jq .enabled 2>"$TMP/err") \
  || die "can't read private vulnerability reporting on $REPO: $(cat "$TMP/err")"
case $pvr in
  true) same "private vulnerability reporting on" ;;
  false) change "turn on private vulnerability reporting" \
           gh api -X PUT "repos/$REPO/private-vulnerability-reporting" ;;
  *) die "unexpected reply for private vulnerability reporting on $REPO: $pvr" ;;
esac

# --- 5. Labels ---------------------------------------------------------------
echo "labels:"
gh api --paginate "repos/$REPO/labels?per_page=100" --jq '.[] | {name, color, description}' \
  | jq -s . >"$TMP/labels.json"
count=$(jq length "$HERE/labels.json")
for ((i = 0; i < count; i++)); do
  want=$(jq -c ".[$i]" "$HERE/labels.json")
  name=$(jq -r .name <<<"$want")
  color=$(jq -r .color <<<"$want")
  description=$(jq -r .description <<<"$want")
  have=$(jq -c --arg n "$name" \
    'map(select((.name | ascii_downcase) == ($n | ascii_downcase))) | .[0] // empty' "$TMP/labels.json")
  if [[ -z $have ]]; then
    change "create label \"$name\"" gh api -X POST "repos/$REPO/labels" \
      -f name="$name" -f color="$color" -f description="$description"
  elif jq -n -e --argjson w "$want" --argjson h "$have" \
      '$w.name == $h.name and ($w.color | ascii_downcase) == ($h.color | ascii_downcase)
       and $w.description == ($h.description // "")' >/dev/null; then
    same "label \"$name\""
  else
    old=$(jq -r .name <<<"$have")
    jq -rn --argjson w "$want" --argjson h "$have" '
      (if $w.name != $h.name then "      name: \($h.name | tojson) -> \($w.name | tojson)" else empty end),
      (if ($w.color | ascii_downcase) != ($h.color | ascii_downcase)
       then "      color: \($h.color) -> \($w.color)" else empty end),
      (if $w.description != ($h.description // "")
       then "      description: \($h.description // "" | tojson) -> \($w.description | tojson)" else empty end)'
    change "update label \"$old\"" gh api -X PATCH \
      "repos/$REPO/labels/$(jq -rn --arg n "$old" '$n | @uri')" \
      -f new_name="$name" -f color="$color" -f description="$description"
  fi
done
jq -r --slurpfile w "$HERE/labels.json" '
  ($w[0] | map(.name | ascii_downcase)) as $names
  | .[] | select(.name | ascii_downcase as $n | $names | index($n) | not) | .name' \
  "$TMP/labels.json" | while IFS= read -r extra; do
  echo "  left alone (not in the baseline): \"$extra\""
done

# --- Summary -----------------------------------------------------------------
if ((!APPLY)); then
  echo "$REPO: $CHANGES change(s) to make; dry run, nothing changed (re-run with --apply)"
elif ((FAILED)); then
  echo "$REPO: $((CHANGES - FAILED)) change(s) applied, $FAILED FAILED (see above)"
  exit 1
else
  echo "$REPO: $CHANGES change(s) applied"
fi
