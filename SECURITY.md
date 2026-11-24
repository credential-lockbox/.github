# Security policy

This is the default security policy for the repositories in the [credential-lockbox](https://github.com/credential-lockbox) organization. A repository with its own `SECURITY.md` follows that file instead. Its scope section says what that project claims to defend against.

## Supported versions

Each repository is versioned on its own. Security fixes go into its latest release only. Older releases get no backports, so upgrade to the latest.

## Reporting a problem

**Please don't open a public issue for a security problem.**

The supported channel is a **GitHub private security advisory** on the repository the problem is in:

1. Open that repository's **Security** tab and choose **Report a vulnerability**. On a narrow window the tab may be under the "…" menu. You need to be signed in to GitHub. Direct links:
   - credential-lockbox: <https://github.com/credential-lockbox/credential-lockbox/security/advisories/new>
   - credential-lockbox-muse: <https://github.com/credential-lockbox/credential-lockbox-muse/security/advisories/new>
   - this organization's shared files (`.github`) or the website: <https://github.com/credential-lockbox/.github/security/advisories/new>
2. Describe the problem, how to reproduce it, and the version affected.
3. Submit it. Only you and the repository's maintainers see the report. The report, any proof of concept, the fix and the disclosure timing are all discussed there.

If you can't use a private advisory, open a **public** issue with the **Security contact request** form in that repository. The form asks for no details, and the maintainer will arrange a private channel.

Documentation problems that don't weaken a security property can be reported as normal issues. There's no embargo expectation for those.

## Please include

- What the problem is and what it lets an attacker do.
- Steps to reproduce, or a proof of concept. Use a project's published test keys, never a real key or credential.
- The repository and version (the release tag, or the commit you used).
- Your platform and tool versions.
- Whether it reproduces with the project used exactly as its instructions say, or only with a changed setup.

## What to expect

- **An acknowledgment** once the maintainer sees the report. This is a one-person project, so response times vary.
- **A coordinated fix and disclosure timeline**, agreed in the advisory.
- **Credit in the release notes** if you want it. Anonymous reports are fine too.
- **No monetary reward.** There's no bug bounty.

## Scope

**In scope**

- A way a project's documented guarantees fail when it's used as its instructions say, or wording that overstates what is defended.
- The scripts and code themselves: input that gets past a documented check, or a secret in output or logs.
- A repository's GitHub Actions workflows: injection through `${{ github.event.* }}` expressions in `run:` blocks, token permissions, or anything that lets a pull request's content run with more than read access.
- The integrity of what a release publishes.

**Out of scope**

- Anything a project's threat model lists as not defended. A report that one of those isn't defended is a documentation discussion, not a vulnerability.
- Vulnerabilities in the tools a project uses (`age`, Python, `bash`, PowerShell and the like). Report those upstream.
- Vulnerabilities in Muse, its platform or its connectors. Report those to Meta.
- Attacks that already need shell access as the agent's account, or the private key.

See also each repository's `LICENSE` for the warranty disclaimer.
