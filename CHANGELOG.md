# Changelog

All notable changes to KubeLynx are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Renamed the project from Kubediag to KubeLynx.
- Renamed the CLI command from `kubediag` to `kubelynx`.
- Relicensed the project to Apache License 2.0.
- Read the version from the root `VERSION` file instead of a duplicated constant.
- Install into `${XDG_DATA_HOME:-$HOME/.local/share}/kubelynx` with a symlink at `~/.local/bin/kubelynx`.
- Stopped treating `gnome-terminal` and `git` as mandatory runtime dependencies.
- Documented Linux as the supported platform, with macOS as best-effort.

### Added

- `NOTICE`, community files, smoke tests, Makefile checks, and GitHub Actions CI/release workflows.

### Security

- Temporary files now use `mktemp` and per-process cleanup instead of predictable `$$` paths and broad `/tmp` globs.
- AI provider API keys are kept out of prompts and diagnostic output; Gemini keys are sent as a header rather than a URL query parameter.
