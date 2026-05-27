# Repository Upstream/Midstream Synchronization Management

## Overview

This project manages the synchronization between upstream open-source repositories and their corresponding midstream (Red Hat internal) repositories. The goal is to maintain consistency between the upstream Konveyor project repositories and their midstream counterparts in the migtools organization.

## Configuration File Format

The project uses `repos.yaml` as its central configuration file with the following structure:

```yaml
upstream_org: <github_organization>      # The upstream GitHub organization
midstream_org: <github_organization>     # The midstream GitHub organization
midstream_prefix: <string>                # Prefix added to repo names in midstream
branch: <branch_name>                     # Target branch to synchronize
repos:                                    # List of repository names to manage
  - <repo_name>
  - <repo_name>
  ...
```

### Current Configuration

- **Upstream Organization**: `konveyor` - The main Konveyor open-source project
- **Midstream Organization**: `migtools` - Red Hat's internal migration tools organization
- **Midstream Prefix**: `mta-` - All midstream repos are prefixed with "mta-" (Migration Toolkit for Applications)
- **Target Branch**: `main` - The branch being synchronized between upstream and midstream
- **Managed Repositories**: 15 repositories including operator, UI, hub, analyzers, and various addons

### Repository Mapping

Each repository follows this naming pattern:
- **Upstream**: `github.com/konveyor/<repo_name>`
- **Midstream**: `github.com/migtools/mta-<repo_name>`

Example:
- `github.com/konveyor/operator` → `github.com/migtools/mta-operator`
- `github.com/konveyor/tackle2-ui` → `github.com/migtools/mta-tackle2-ui`

## Project Goals

1. **Automated Cloning**: Clone all upstream repositories locally for management
2. **Remote Configuration**: Set up proper git remotes for both upstream and midstream
3. **Branch Synchronization**: Keep the specified branch (release-0.9) in sync between repositories
4. **Conflict Resolution**: Handle merge conflicts and differences between upstream and midstream
5. **Automated Updates**: Streamline the process of pulling upstream changes and pushing to midstream

## Scripts

### clone.sh
Clones all upstream repositories and configures them with proper remotes and git settings.

**Features:**
- Clones repositories from the upstream organization if they don't exist locally
- Adds midstream remote for each repository
- Configures git user email and SSH settings for each repository
- Idempotent - safe to run multiple times

**Git Configuration Applied:**
```ini
[user]
    email = dymurray@redhat.com
[core]
    sshCommand = ssh -i ~/.ssh/dymurray_rsa -o IdentitiesOnly=yes
```

### sync-and-rebase.sh
Rebases midstream repositories against upstream and manages git submodule updates.

**Features:**
- Rebases midstream branch against upstream branch
- Automatically detects and updates git submodules
- Commits submodule changes with standardized message
- Force pushes to midstream after successful rebase
- Configurable workflow with command-line flags

**Command-Line Options:**
- `--branch <name>` - Override the branch from repos.yaml configuration
- `--repos <repo1,repo2>` - Process specific repositories (comma-separated)
- `--no-commit` - Update submodules but don't commit changes
- `--no-push` - Don't push changes to midstream remote
- `--help` - Show usage information

**Usage Examples:**
```bash
# Sync all repositories on default branch
./sync-and-rebase.sh

# Sync specific repo without committing or pushing (dry run)
./sync-and-rebase.sh --branch main --repos=kantra --no-commit --no-push

# Sync multiple repos on a different branch
./sync-and-rebase.sh --branch release-0.9 --repos=operator,tackle2-ui

# Process all repos but don't push (review changes first)
./sync-and-rebase.sh --no-push
```

**Workflow:**
1. Fetches latest from upstream and midstream remotes
2. Checks out midstream branch (creates if doesn't exist)
3. Rebases against upstream branch
4. Checks for .gitmodules and updates submodules if present
5. Commits submodule changes with message: "git submodule updates for <branch>"
6. Force pushes to midstream remote

**Error Handling:**
- Detects uncommitted changes and warns before proceeding
- Stops on rebase conflicts and provides resolution instructions
- Reports failed repositories in summary
- Validates repository state before operations

### sync-and-merge.sh
Merges upstream changes into midstream repositories and manages git submodule updates.

**Features:**
- Merges upstream branch into midstream branch (preserves commit history)
- Automatically detects and updates git submodules
- Commits submodule changes with standardized message
- Regular push to midstream (no force push required)
- Configurable workflow with command-line flags

**Command-Line Options:**
- `--branch <name>` - Override the branch from repos.yaml configuration
- `--repos <repo1,repo2>` - Process specific repositories (comma-separated)
- `--no-commit` - Update submodules but don't commit changes
- `--no-push` - Don't push changes to midstream remote
- `--help` - Show usage information

**Usage Examples:**
```bash
# Merge all repositories on default branch
./sync-and-merge.sh

# Merge specific repo without committing or pushing (dry run)
./sync-and-merge.sh --branch main --repos=kantra --no-commit --no-push

# Merge multiple repos on a different branch
./sync-and-merge.sh --branch release-0.9 --repos=operator,tackle2-ui

# Process all repos but don't push (review changes first)
./sync-and-merge.sh --no-push
```

**Workflow:**
1. Fetches latest from upstream and midstream remotes
2. Checks out midstream branch (creates if doesn't exist)
3. Merges upstream branch (preserves history)
4. Checks for .gitmodules and updates submodules if present
5. Commits submodule changes with message: "git submodule updates for <branch>"
6. Regular push to midstream remote

**When to Use Merge vs Rebase:**
- **Use merge** when you want to preserve the complete history and avoid force pushing
- **Use merge** when midstream has unique commits that should be preserved in the history
- **Use rebase** when you want a linear history and midstream changes should appear on top
- **Use rebase** when you're comfortable with force pushing to midstream

### Future Scripts (Planned)
- `status.sh` - Check synchronization status of all repositories
- `diff.sh` - Show differences between upstream and midstream branches
- `validate.sh` - Verify all repositories are properly configured

## Workflow

1. **Initial Setup**: Run `clone.sh` to set up all repositories locally
2. **Sync and Rebase**: Run `sync-and-rebase.sh` to rebase midstream against upstream
3. **Review Changes**: Use `--no-push` flag to review changes before pushing
4. **Resolve Conflicts**: Handle any merge conflicts that arise during rebase
5. **Update Submodules**: Automatically handled by sync-and-rebase.sh
6. **Push Updates**: Force push rebased changes to midstream

## Repository List

The following repositories are currently managed:
1. operator - Core operator for the migration toolkit
2. java-analyzer-bundle - Java application analysis tools
3. analyzer-lsp - Language Server Protocol analyzer
4. tackle2-hub - Central hub component
5. tackle2-seed - Seed data and initialization
6. tackle2-ui - User interface
7. tackle2-addon - Core addon framework
8. static-report - Static report generation
9. kantra - Konveyor analyzer tool
10. rulesets - Migration rulesets
11. tackle2-addon-analyzer - Analyzer addon
12. tackle2-addon-discovery - Discovery addon
13. tackle2-addon-platform - Platform addon
14. kai - Konveyor AI component
15. c-sharp-analyzer-provider - C# language analyzer

## Prerequisites

- Git installed and configured
- SSH key (`~/.ssh/dymurray_rsa`) with access to both GitHub organizations
- Proper permissions for both konveyor and migtools organizations
- yq or similar YAML parser (for script automation)

## Security Considerations

- SSH keys are configured per-repository to ensure secure authentication
- The specific SSH key is isolated using `IdentitiesOnly=yes` to prevent key leakage
- All operations use SSH protocol for secure communication with GitHub

## Maintenance

This configuration should be updated when:
- New repositories are added to the Konveyor project
- Repository names change in either organization
- The target branch for synchronization changes
- Authentication requirements change