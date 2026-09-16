# Contributing to KubeLynx

Thanks for contributing. KubeLynx is a Bash CLI. Keep changes focused, auditable, and consistent with the existing interactive `fzf` UX.

## Fork, clone, and branch

1. Fork [ielyaakouby/kubelynx](https://github.com/ielyaakouby/kubelynx).
2. Clone your fork:

   ```bash
   git clone https://github.com/<your-username>/kubelynx.git
   cd kubelynx
   ```

3. Create a feature branch from `main`:

   ```bash
   git checkout -b feature/short-description
   ```

## Development requirements

Required to run the CLI against a cluster:

- Bash (4.4+ recommended)
- `kubectl`
- `fzf`
- `jq`

Required to run project checks:

- `make`
- `shellcheck`
- `shfmt` (`https://github.com/mvdan/sh`)
- `zip` (release packaging)

A Kubernetes cluster is **not** required for `make check`.

## Repository architecture

- `bin/kubelynx.sh` — CLI entrypoint
- `config/defaults.sh` — overridable defaults (AI models, `TMPDIR`)
- `src/k8s/` — sourced modules (menus, diagnostics, actions)
- `installer/` — user-space install, update, uninstall
- `tests/` — smoke tests that must not touch a cluster
- `VERSION` — single source of truth for the version string

Modules under `src/k8s/` are sourced at startup. Put new functions in the matching directory and keep names descriptive.

## Run the CLI locally

From the clone, without installing:

```bash
./bin/kubelynx.sh --help
./bin/kubelynx.sh --version
./bin/kubelynx.sh
```

Development symlink (optional):

```bash
./installer/install.sh --dev
```

Library mode (loads functions, does not open the menu or contact the cluster):

```bash
./bin/kubelynx.sh ok
```

## Checks

Run everything before opening a pull request:

```bash
make check
```

That runs:

1. `bash -n` on all `*.sh` files
2. ShellCheck
3. `shfmt` in diff/check mode (does not rewrite files)
4. `tests/run.sh`

Format locally with:

```bash
make format
```

`make format` is the only command that rewrites shell files. CI never auto-formats.

## ShellCheck and shfmt

- Fix real issues (quoting, word splitting, unsafe `rm`, missing `cd` checks).
- Do not add repository-wide ShellCheck disables to make CI green.
- A local `# shellcheck disable=` comment is acceptable when it is narrowly scoped and has a one-line justification.
- Indentation is 4 spaces (`shfmt -i 4 -ci -bn`), matching `.editorconfig`.

## Tests

- Tests must not modify a Kubernetes cluster, delete cluster resources, call AI APIs, or require secrets.
- Prefer small Bash smoke tests under `tests/test_*.sh`.
- If you change install/update/version behavior, extend the tests.

## Commit and pull request expectations

- Keep pull requests focused on one change.
- Do not mix formatting-only rewrites with functional changes unless the PR is explicitly a format pass.
- Describe why the change is needed, how it was tested, and any security impact.
- Update README or other docs when user-visible behavior changes.
- Do not commit kubeconfig files, API keys, or `.env` files.

There is no CLA and no DCO requirement.

## Releases

Maintainers publish releases by tagging `main`. See [docs/RELEASING.md](docs/RELEASING.md).
