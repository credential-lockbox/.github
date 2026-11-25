# Credential Lockbox

Encrypted handoff and storage so AI agents can use secrets that never enter the chat or touch disk. Muse today; others once they can run their own processes.

You encrypt a credential on your own device to your agent's public key. Only ciphertext passes through the chat. The agent decrypts it inside the process that needs it. Nothing decrypted is printed, shown to the model, or written to disk by this design. The website is <https://credential-lockbox.github.io>.

## Projects

| Project | What it is | Status |
| --- | --- | --- |
| [credential-lockbox](https://github.com/credential-lockbox/credential-lockbox) | The core: the scripts on your side and the agent's, the threat model, and the setup guide. | Moved here from [cmeans/muse-field-kit](https://github.com/cmeans/muse-field-kit) with its history; [latest release](https://github.com/credential-lockbox/credential-lockbox/releases/latest). |
| [credential-lockbox-muse](https://github.com/credential-lockbox/credential-lockbox-muse) | A browser page your Muse builds for you, so you can lock a credential from your phone. No terminal needed. | Coming soon. |
| s3-blob-store, s3-blob-store-muse | A small AWS store for the ciphertext, and its Muse setup. Built for credential ciphertext, and usable for any small, already-encrypted blob that fits its by-label, no-list design. | Planned to move here. Today at [cmeans/s3-blob-store](https://github.com/cmeans/s3-blob-store) and [cmeans/s3-blob-store-muse](https://github.com/cmeans/s3-blob-store-muse). |

## Reporting a security problem

Privately, never in a public issue. See [SECURITY.md](https://github.com/credential-lockbox/.github/blob/main/SECURITY.md).
