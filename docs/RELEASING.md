# Releasing KubeLynx

KubeLynx follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

Examples:

- `3.0.1` — bug fix
- `3.1.0` — backward-compatible feature
- `4.0.0` — breaking change

Do **not** tag from GitHub Actions on ordinary pushes. A release exists only when a maintainer creates and pushes an annotated tag.

## Steps

1. Ensure `main` is clean and up to date with the default remote.
2. Run `make check`.
3. Update `VERSION` to the version being released (no `v` prefix).
4. Update `CHANGELOG.md` if appropriate (move `[Unreleased]` notes into a dated section).
5. Commit the version and changelog changes.
6. Merge to `main`.
7. Tag the release:

   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   ```

   The tag version (`v3.0.0`) must match `VERSION` (`3.0.0`).
8. Push the tag:

   ```bash
   git push origin vX.Y.Z
   ```

9. GitHub Actions (`.github/workflows/release.yml`) validates that the tag matches `VERSION`.
10. The workflow runs `make check` and refuses to publish if syntax, ShellCheck, formatting, or tests fail.
11. The workflow builds `kubelynx-vX.Y.Z.tar.gz`, `kubelynx-vX.Y.Z.zip`, and `SHA256SUMS`.
12. A GitHub Release is created for the tag, with automatically generated notes and the artifacts attached.

## After publishing

- Open the GitHub Release and confirm the three assets are present.
- Verify checksums on Linux:

  ```bash
  sha256sum -c SHA256SUMS
  ```

- Extract the tarball and run:

  ```bash
  ./kubelynx-vX.Y.Z/bin/kubelynx.sh --version
  ./kubelynx-vX.Y.Z/installer/install.sh
  ```

Do not create tags for experiments on `main`. If `VERSION` and the tag disagree, the release workflow fails on purpose.
