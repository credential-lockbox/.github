# Contributing

Thanks for your interest. These projects are small and one-person, and they're security patterns, so changes come in a particular way. This is the default guide for the repositories in the [credential-lockbox](https://github.com/credential-lockbox) organization. A repository with its own `CONTRIBUTING.md` follows that file instead, and its README says how to run its checks.

## How to contribute: issues, not pull requests

**Pull requests are opened by the project's collaborators.** Everyone can read them, and everyone can open an issue. So the way to contribute is an issue in the repository concerned:

- **Bug report:** something doesn't work the way the docs say.
- **Feature request:** a new capability, or a change to how something works.
- **Platform test report:** what happened when you ran a project on a platform or tool version that isn't tested (macOS, Windows, a phone, an older `bash`).
- **Security problems:** an exploitable flaw never goes in a public issue. Report it privately, as [SECURITY.md](https://github.com/credential-lockbox/.github/blob/main/SECURITY.md) says.

A good issue is specific: the project, its version, your platform, what you ran, what you expected and what happened, and the output with any secret removed. A proposed fix in the issue (a diff, or the exact wording) is welcome. The maintainer's side turns an agreed fix into a pull request and credits you in it.

Why not outside pull requests? The code here handles credentials, and every change to it is reviewed in several rounds before it merges. Taking changes as issues keeps outside code from running in these repositories' CI, and keeps every change on that review path.

## License of contributions

**By contributing (an issue's proposed fix, a diff, or text), you agree that it may be used under the MIT License**, the license of the project. You keep your copyright, and you grant everyone the MIT License's permissions for what you contributed. Please don't attach extra terms (payment, bounty claims, restrictions on use): they have no effect, and you'll be asked to drop them.

There are no bug bounties or paid contributions. Sponsoring the maintainer is separate: it supports the projects as a whole and buys no change, priority or review.

## What needs agreement first

- **Mechanism changes:** the crypto, the payload format, how input is read, key generation and permissions. A project's `SETUP.md`, where it has one, lists what counts. Otherwise, ask on the issue. These need the maintainer's agreement before anyone writes them, and for the Muse projects, Muse's review too.
- **Designs and plans** for larger work are written and reviewed first, then implemented.
- **New dependencies** for the people who use a project. Each one costs every adopter an install, so it's the maintainer's call. Test-only and CI-only tools are fine.

## How a change is reviewed (collaborators)

One concern per pull request, branched from `main`. Each PR body has a `## Summary`, a `## QA` checklist a reviewer can run, and `Closes #N` for any issue it fixes. The pull request template has these sections.

Labels track the review:
1. Where a repository has CI, it runs on every push (`Awaiting CI`). Once it passes, or right away in a repository without CI, the PR is `Ready for QA`.
2. QA applies `QA Failed` with findings, or `Ready for QA Signoff`.
3. For the Muse projects, Muse reviews too (`Muse Approved` or `Muse Failed`).
4. The maintainer applies `QA Approved` and approves the latest push in a review. Only then is the PR merged. The branch rules enforce the approval; the label is the signal.

Any push starts the review again.

## Style

- Messages never print a secret or anything derived from one, and errors say what to do next.
- Docs and messages use American English spelling (behavior, color, license).

## Contact

Open an issue. This is a one-person project, so response times vary.
