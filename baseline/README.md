# Repository baseline

`baseline.sh` gives every repository in the credential-lockbox org the same rulesets, settings, vulnerability alerts and labels. The org is on GitHub Free, where org-wide rulesets aren't available, so the script applies the same package to one repo at a time. The list of what it manages is in the script's header.

## Running it

Run it as an org owner, from your own `gh` login. The org's bot apps have no Administration permission, by design.

```sh
# Dry run: shows what would change, changes nothing.
baseline/baseline.sh --check ci-ok --check "QA Gate" credential-lockbox/credential-lockbox

# Apply.
baseline/baseline.sh --apply --check ci-ok --check "QA Gate" credential-lockbox/credential-lockbox
```

`--check` is the only per-repo input: the status checks that must pass before a merge to `main`. Give the repo's full list every time, since they aren't stored anywhere. Leave it out for a repo with no CI (this `.github` repo, for one). If you leave it out and the repo's `main` ruleset already requires checks, the script stops and names them instead of removing them. Pass `--no-checks` if you do mean to remove them. A dry run names every required check it would add or remove.

Re-running is safe. The script reads the current state and changes only what differs, and on a repo that already matches it reports `0 change(s)`. If a change fails, it prints `FAILED` with GitHub's reply, carries on with the rest, and exits 1. Run it again once the cause is fixed.

## Payloads

| File | What it is |
|---|---|
| `rulesets/main.json` | The `main` ruleset. The script adds the required status checks from `--check`. |
| `rulesets/release-tags.json` | The release tag ruleset (`v*`, `*-v*`). |
| `settings.json` | Repository settings. |
| `labels.json` | The label set. |

Change the baseline by changing these files in a pull request, then re-run the script on each repo.

## Order for a new repo

Run it after the repo's first history is on `main`. The `main` ruleset requires pull requests and blocks force pushes, so a repo that is about to receive an imported history (such as the move from `cmeans/muse-field-kit`) gets that push first, and the baseline right after.
