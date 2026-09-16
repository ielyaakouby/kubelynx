# Security Policy

## Reporting a vulnerability

Do **not** open a public GitHub issue for a security vulnerability when responsible disclosure is appropriate.

Use [GitHub private vulnerability reporting](https://github.com/ielyaakouby/kubelynx/security/advisories/new) for this repository.

The public issue tracker is for ordinary bugs and feature requests. If private reporting is unavailable, describe the issue at a high level in an issue **without** including exploits, credentials, or cluster data, and wait for maintainer contact.

## Sensitive areas in KubeLynx

KubeLynx is a local CLI. It uses the same Kubernetes access as the operator's `kubectl` / `KUBECONFIG`. Treat anything it can read as available to the person running it.

Particularly sensitive areas:

- **Kubernetes credentials** — kubeconfig files, tokens, client certificates, and cloud identity plugins. KubeLynx does not store a separate cluster credential. It uses whatever `kubectl` would use.
- **Command execution** — several actions run `kubectl exec`, port-forward, or start debug pods. These are constrained only by the current Kubernetes RBAC identity.
- **Secrets and pod logs** — inspect/log/secret viewers can display Secret data and application logs. Logs often contain tokens or passwords that Kubernetes does not mark as Secret objects.
- **Temporary files** — diagnostics may write YAML, logs, or describe output under `$TMPDIR`. Files are owned by the current user and are cleaned up for the current process. They are not encrypted.
- **AI provider API keys** — `GEMINI_API_KEY` and `OPENAI_API_KEY` are read from the environment. They must not be committed, logged, or pasted into issues.

## AI integrations

AI analysis is optional. When enabled, KubeLynx sends **selected diagnostic context** (for example pod logs and events, plus namespace/pod/status metadata) to an external provider:

- Google Gemini
- OpenAI
- a local Ollama server

That data leaves the machine running KubeLynx (except for local Ollama). Do not assume redaction is complete. Obvious Kubernetes Secret objects are not intentionally included in AI prompts, but **log lines and events can still contain credentials**. Review data before enabling AI in sensitive environments.

Do not put API keys in prompts, debug prints, or GitHub issues. Example configuration uses placeholders only:

```bash
export GEMINI_API_KEY="..."
export OPENAI_API_KEY="..."
```

## What this project does not claim

KubeLynx does not sandbox `kubectl`, does not replace Kubernetes RBAC, and does not guarantee that diagnostic output is free of secrets.
