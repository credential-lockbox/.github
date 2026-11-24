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

`--check` is the only per-repo input: the status checks that must pass before a merge to `main`. Leave it out for a repo with no CI (this `.github` repo, for one). Re-running is safe. The script reads the current state and changes only what differs, and on a repo that already matches it reports `0 change(s)`.

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
