# Konveyor Upstream → Midstream Sync

Tooling to keep the upstream [Konveyor](https://github.com/konveyor) repositories in sync
with their midstream Red Hat counterparts in the [migtools](https://github.com/migtools)
organization (the **M**igration **T**oolkit for **A**pplications, hence the `mta-` prefix).

The workflow is two steps:

1. **`./clone.sh`** — clone every managed upstream repo locally and wire up its `midstream`
   remote (run once, then re-run any time to refresh).
2. **`./sync-and-merge.sh`** — merge the latest upstream changes into each midstream branch,
   update submodules, and push to midstream.

Each repo is mapped as:

| Upstream                              | Midstream                                      |
|---------------------------------------|------------------------------------------------|
| `github.com/konveyor/<repo>`          | `github.com/migtools/mta-<repo>`               |
| `github.com/konveyor/operator`        | `github.com/migtools/mta-operator`             |

---

## Prerequisites

- **bash** and **git**
- Standard `grep` / `awk` (the scripts parse YAML with these — no `yq` required)
- **SSH access** to both the `konveyor` and `migtools` GitHub organizations, with a loaded
  SSH key. All remotes use SSH (`git@github.com:...`).

---

## Configuration

### `repos.yaml` (shared, committed)

Defines the organizations, the midstream prefix, the branch to sync, and the list of
managed repositories:

```yaml
upstream_org: konveyor      # upstream GitHub org
midstream_org: migtools     # midstream GitHub org
midstream_prefix: mta-      # prefix on midstream repo names
branch: main                # branch to keep in sync
repos:
  - operator
  - java-analyzer-bundle
  - analyzer-lsp
  - tackle2-hub
  - tackle2-ui
  - static-report
  - kantra
  - tackle2-addon-analyzer
  - tackle2-addon-discovery
  - tackle2-addon-platform
  - kai
  - c-sharp-analyzer-provider
```

### `config.yaml` (optional, per-user, gitignored)

Lets you override the git identity that `clone.sh` writes into each cloned repo. It is
**optional** — if `config.yaml` is absent (or a value is left unset), `clone.sh` falls back
to your **existing git config** (`user.email`) and your **default SSH** setup.

To use it, copy the template and edit:

```bash
cp config.yaml.example config.yaml
```

```yaml
git_email: you@example.com       # written as git user.email in each repo
ssh_key: ~/.ssh/your_key         # used as: ssh -i <key> -o IdentitiesOnly=yes
```

`config.yaml` is listed in `.gitignore`, so your personal values never get committed.

---

## Quick start

```bash
# 1. (optional) set a per-repo git identity / SSH key
cp config.yaml.example config.yaml   # then edit, or skip to use your global git config

# 2. clone all repos and configure remotes
./clone.sh

# 3. merge upstream into midstream and push
./sync-and-merge.sh
```

---

## `clone.sh`

Clones (or, if already present, fetches) every repo listed in `repos.yaml` and configures
it. It is **idempotent** — safe to re-run any time.

For each repo it:

1. Clones `git@github.com:konveyor/<repo>.git` (or fetches if the directory already exists).
2. Sets `user.email` and the SSH key — from `config.yaml` if present, otherwise leaves your
   existing git config untouched.
3. Adds (or updates) the `midstream` remote pointing at
   `git@github.com:migtools/mta-<repo>.git`.
4. Fetches both remotes and checks out the configured `branch`.

```bash
./clone.sh
```

---

## `sync-and-merge.sh`

Merges the latest upstream changes into each midstream branch and pushes. Merging
**preserves history** and uses a regular (non-force) push.

For each repo it: fetches both remotes → resets the local branch to `midstream/<branch>` →
merges `origin/<branch>` (no fast-forward edits) → updates submodules and commits them →
runs the repo's `scripts/post-sync.sh` hook if present (see below) → pushes to
`midstream/<branch>`. Repos already up-to-date are skipped.

### Post-sync hook

If a managed repo has an executable `scripts/post-sync.sh`, it runs after a successful
merge (or submodule update). Use it to regenerate files derived from upstream content —
e.g. hash-locked `requirements.txt` for Hermeto/Konflux builds, or other midstream-specific
build artifacts. Any tracked-file changes are committed as `post-sync: regenerate
generated files for <branch>`. Honors `--no-commit`. A non-zero exit aborts the push and
marks the repo failed.

Often paired with a `.gitattributes merge=ours` rule so upstream's version of the
generated file doesn't fight the merge. `clone.sh` registers the `ours` driver
(`git config merge.ours.driver true`) on every clone so the attribute actually takes
effect — git ships the merge *strategy* but not the per-file *driver*.

### Flags

| Flag | Default | Effect |
|------|---------|--------|
| `--branch <name>` | value from `repos.yaml` (`main`) | Sync a different branch instead of the one in `repos.yaml`. |
| `--repos <list>` | all repos in `repos.yaml` | Process only the comma-separated repos, e.g. `--repos=kantra,operator`. |
| `--no-commit` | commits enabled | Update submodules but do **not** commit the submodule pointer changes. |
| `--no-push` | push enabled | Do everything locally but do **not** push to midstream (good for reviewing first). |
| `--no-force-reset` | force-reset enabled | Don't hard-reset the local branch to `midstream/<branch>` before merging (keeps local state). |
| `--no-skip` | skip enabled | Process every repo even if it's already up-to-date with upstream. |
| `--help` | — | Print usage and exit. |

### Examples

```bash
# Merge and push all repos on the default branch
./sync-and-merge.sh

# Dry run a single repo: no commit, no push
./sync-and-merge.sh --branch main --repos=kantra --no-commit --no-push

# Merge specific repos on a different branch
./sync-and-merge.sh --branch release-0.9 --repos=operator,tackle2-ui

# Process all repos but review before pushing
./sync-and-merge.sh --no-push
```

---

## Merge vs. rebase

`sync-and-merge.sh` **preserves the full history** and uses a regular push — use it when
midstream has unique commits worth keeping, or when you want to avoid force-pushing.

`sync-and-rebase.sh` is the alternative: it rebases midstream on top of upstream for a
**linear history** and **force-pushes** the result. It accepts the same flags as the merge
script (`--branch`, `--repos`, `--no-commit`, `--no-push`, `--no-force-reset`, `--no-skip`).

---

## Resolving merge conflicts

If a merge can't complete cleanly, the script stops and reports the repo. Resolve it
manually:

```bash
# abort and leave the repo untouched
cd <repo> && git merge --abort

# or resolve the conflicts, then continue
cd <repo>
# ...edit conflicted files...
git add .
git merge --continue
```

Then re-run `./sync-and-merge.sh` (optionally with `--repos=<repo>`) to finish and push.
