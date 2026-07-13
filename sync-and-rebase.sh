#!/bin/bash

# Sync and Rebase Script
# This script rebases midstream repositories against upstream and updates git submodules

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Default values
COMMIT_CHANGES=true
PUSH_CHANGES=true
SPECIFIC_REPOS=""
OVERRIDE_BRANCH=""
FORCE_RESET=true
SKIP_IF_CURRENT=true

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Sync and rebase midstream repositories against upstream, updating git submodules as needed.

OPTIONS:
    --branch <name>     Override the branch specified in repos.yaml
    --repos <list>      Process specific repositories (comma-separated)
                        Example: --repos=kantra,operator,tackle2-ui
    --no-commit         Update submodules but don't commit changes
    --no-push          Don't push changes to midstream remote
    --no-force-reset    Don't reset local repos to midstream state (default: do reset)
    --no-skip           Process all repos even if already up-to-date (default: skip)
    --help             Show this help message

EXAMPLES:
    # Rebase and push all repos on default branch
    $0

    # Rebase specific repo without committing or pushing
    $0 --branch main --repos=kantra --no-commit --no-push

    # Rebase multiple repos on a different branch
    $0 --branch release-0.9 --repos=operator,tackle2-ui

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --branch)
            OVERRIDE_BRANCH="$2"
            shift 2
            ;;
        --repos)
            SPECIFIC_REPOS="$2"
            shift 2
            ;;
        --no-commit)
            COMMIT_CHANGES=false
            shift
            ;;
        --no-push)
            PUSH_CHANGES=false
            shift
            ;;
        --no-force-reset)
            FORCE_RESET=false
            shift
            ;;
        --no-skip)
            SKIP_IF_CURRENT=false
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if repos.yaml exists
if [ ! -f "repos.yaml" ]; then
    print_error "repos.yaml not found in current directory"
    exit 1
fi

# Parse configuration from repos.yaml
UPSTREAM_ORG=$(grep "^upstream_org:" repos.yaml | awk '{print $2}')
MIDSTREAM_ORG=$(grep "^midstream_org:" repos.yaml | awk '{print $2}')
MIDSTREAM_PREFIX=$(grep "^midstream_prefix:" repos.yaml | awk '{print $2}')
CONFIG_BRANCH=$(grep "^branch:" repos.yaml | awk '{print $2}')

# Use override branch if provided, otherwise use config branch
BRANCH="${OVERRIDE_BRANCH:-$CONFIG_BRANCH}"

if [ -z "$UPSTREAM_ORG" ] || [ -z "$MIDSTREAM_ORG" ] || [ -z "$MIDSTREAM_PREFIX" ] || [ -z "$BRANCH" ]; then
    print_error "Failed to parse configuration from repos.yaml"
    exit 1
fi

print_status "Configuration:"
print_status "  Upstream org: $UPSTREAM_ORG"
print_status "  Midstream org: $MIDSTREAM_ORG"
print_status "  Midstream prefix: $MIDSTREAM_PREFIX"
print_status "  Branch: $BRANCH"
print_status "  Commit changes: $COMMIT_CHANGES"
print_status "  Push changes: $PUSH_CHANGES"
print_status "  Force reset: $FORCE_RESET"
print_status "  Skip if current: $SKIP_IF_CURRENT"
echo ""

# Determine which repositories to process
if [ -n "$SPECIFIC_REPOS" ]; then
    # Convert comma-separated list to space-separated
    REPOS=$(echo "$SPECIFIC_REPOS" | tr ',' ' ')
    print_status "Processing specific repositories: $REPOS"
else
    # Extract all repositories from repos.yaml
    REPOS=$(awk '/^repos:/{flag=1; next} /^[^-]/{flag=0} flag && /^- /{print $2}' repos.yaml)
    print_status "Processing all repositories from repos.yaml"
fi

if [ -z "$REPOS" ]; then
    print_error "No repositories to process"
    exit 1
fi

# Count total repositories
TOTAL_REPOS=$(echo "$REPOS" | wc -w)
CURRENT=0
FAILED_REPOS=""
SKIPPED_REPOS=""

print_status "Processing $TOTAL_REPOS repositories"
echo ""

# Function to check if there are uncommitted changes
check_uncommitted_changes() {
    if [ -n "$(git status --porcelain)" ]; then
        return 0
    else
        return 1
    fi
}

# Function to reset local repository to midstream state
reset_to_midstream() {
    local branch=$1
    if git show-ref --verify --quiet "refs/remotes/midstream/$branch"; then
        print_status "Resetting local branch to midstream/$branch..."
        git reset --hard "midstream/$branch"
        git clean -fd

        # Also reset submodules if they exist
        if [ -f ".gitmodules" ]; then
            print_status "Resetting submodules..."
            git submodule foreach --recursive git reset --hard
            git submodule update --init --recursive
        fi

        return 0
    else
        # No midstream branch exists, that's ok
        return 1
    fi
}

# Function to check if midstream is already up-to-date with upstream
is_up_to_date() {
    local branch=$1
    # Check if upstream changes are already in current branch
    if git merge-base --is-ancestor "origin/$branch" HEAD; then
        return 0  # Already up-to-date
    else
        return 1  # Needs update
    fi
}

# Function to update git submodules
update_submodules() {
    local repo=$1
    local branch=$2

    if [ -f ".gitmodules" ]; then
        print_status "Found .gitmodules, updating submodules to latest remote commits..."

        # Update submodules to the latest commit on their remote tracking branches
        git submodule update --init --remote --recursive

        # Check if any submodule pointers were actually changed
        if [ -n "$(git status --porcelain)" ]; then
            print_status "Submodules were updated"

            if $COMMIT_CHANGES; then
                # Stage all submodule changes
                git add .

                # Commit the changes
                local commit_msg="git submodule updates for $branch"
                print_status "Committing submodule changes: $commit_msg"
                git commit -m "$commit_msg"
            else
                print_warning "Skipping commit (--no-commit flag set)"
            fi
        else
            print_status "Submodules are already up to date"
        fi
    else
        print_debug "No .gitmodules file found in $repo"
    fi

    return 0
}

# Process each repository
for REPO in $REPOS; do
    CURRENT=$((CURRENT + 1))
    echo "[$CURRENT/$TOTAL_REPOS] Processing: $REPO"
    echo "========================================="

    # Check if repository directory exists
    if [ ! -d "$REPO" ]; then
        print_error "Repository directory $REPO does not exist"
        print_warning "Run ./clone.sh first to clone repositories"
        FAILED_REPOS="$FAILED_REPOS $REPO"
        echo ""
        continue
    fi

    cd "$REPO"

    # Check if it's a git repository
    if [ ! -d ".git" ]; then
        print_error "$REPO is not a git repository"
        cd ..
        FAILED_REPOS="$FAILED_REPOS $REPO"
        echo ""
        continue
    fi

    # Ensure the `ours` merge driver exists on THIS clone so overlay repos'
    # `.gitattributes merge=ours` (e.g. mta-kai's generated requirements.txt / uv.lock)
    # actually takes effect on merge/rebase. Idempotent -- makes the sync self-sufficient
    # on any clone, without depending on a prior clone.sh run or a manual `git config`.
    git config merge.ours.driver true

    # Store current branch for potential restoration
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    # Check if we need to stash changes (only if switching branches)
    if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
        if check_uncommitted_changes; then
            print_warning "Stashing uncommitted changes before switching branches..."
            git stash push -m "sync-script: auto-stash for branch switch"
            STASHED=true
        else
            STASHED=false
        fi
    else
        STASHED=false
    fi

    # Fetch latest from both remotes
    print_status "Fetching latest from upstream (origin)..."
    git fetch origin

    print_status "Fetching latest from midstream..."
    if ! git fetch midstream 2>/dev/null; then
        print_warning "Could not fetch from midstream (repository might not exist)"
    fi

    # Check if the branch exists on upstream
    if ! git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
        print_error "Branch $BRANCH doesn't exist on upstream"
        # Restore stash if we stashed
        if [ "$STASHED" = true ]; then
            print_status "Restoring stashed changes..."
            git stash pop
        fi
        cd ..
        FAILED_REPOS="$FAILED_REPOS $REPO"
        echo ""
        continue
    fi

    # Always ensure we're working with the latest remote state
    # The force reset flag controls how aggressively we reset
    if git show-ref --verify --quiet "refs/remotes/midstream/$BRANCH"; then
        if $FORCE_RESET; then
            # Force reset to midstream (discards local changes)
            reset_to_midstream "$BRANCH"
            print_status "Reset to midstream/$BRANCH"
        else
            # Checkout and update to latest midstream
            print_status "Switching to and updating midstream/$BRANCH..."
            git checkout -B "$BRANCH" "midstream/$BRANCH"

            # Update submodules
            if [ -f ".gitmodules" ]; then
                git submodule foreach --recursive git reset --hard
                git submodule update --init --recursive
            fi
        fi
    else
        # No midstream branch exists, start from upstream
        print_status "No midstream branch found, switching to origin/$BRANCH"
        git checkout -B "$BRANCH" "origin/$BRANCH"

        # Reset submodules for upstream
        if [ -f ".gitmodules" ]; then
            print_status "Initializing submodules from upstream..."
            git submodule foreach --recursive git reset --hard
            git submodule update --init --recursive
        fi
    fi

    # Check for uncommitted changes after potential reset
    if check_uncommitted_changes; then
        print_error "Repository has uncommitted changes after reset. This shouldn't happen."
        git status --short
        cd ..
        FAILED_REPOS="$FAILED_REPOS $REPO"
        echo ""
        continue
    fi

    # Check if we need to do anything
    NEEDS_UPDATE=false
    NEEDS_SUBMODULE_UPDATE=false

    if $SKIP_IF_CURRENT; then
        print_status "Checking if updates are needed..."

        if is_up_to_date "$BRANCH"; then
            print_debug "Already up-to-date with upstream"

            # Check submodules even if main repo is up-to-date
            if [ -f ".gitmodules" ]; then
                print_status "Submodules found, will check for remote updates"
                NEEDS_SUBMODULE_UPDATE=true
            else
                print_status "Repository is fully up-to-date, skipping"
                SKIPPED_REPOS="$SKIPPED_REPOS $REPO"
                cd ..
                echo ""
                continue
            fi
        else
            print_status "Updates needed from upstream"
            NEEDS_UPDATE=true
        fi
    else
        # Force processing even if up-to-date
        NEEDS_UPDATE=true
    fi

    # Perform the rebase if needed
    if [ "$NEEDS_UPDATE" = true ]; then
        print_status "Rebasing against upstream/origin/$BRANCH..."
        if git rebase "origin/$BRANCH"; then
            print_status "Rebase completed successfully"

            # After rebase, update submodules to latest remote if they exist
            if [ -f ".gitmodules" ]; then
                print_status "Updating submodules after rebase..."
                update_submodules "$REPO" "$BRANCH"
            else
                print_debug "No submodules in this repo"
            fi
        else
            print_error "Rebase failed due to conflicts!"
            print_error "Please resolve conflicts manually in $REPO"
            print_status "To abort the rebase, run:"
            echo "  cd $REPO && git rebase --abort"
            print_status "To continue after resolving conflicts, run:"
            echo "  cd $REPO && git rebase --continue"
            cd ..
            FAILED_REPOS="$FAILED_REPOS $REPO"
            echo ""
            continue
        fi
    elif [ "$NEEDS_SUBMODULE_UPDATE" = true ]; then
        # Only update submodules if no rebase was needed but submodules are out of sync
        print_status "Updating submodules (no rebase needed)..."
        update_submodules "$REPO" "$BRANCH"
    fi

    # Run repo-specific post-sync hook if present (regenerate lock files, etc.)
    if ([ "$NEEDS_UPDATE" = true ] || [ "$NEEDS_SUBMODULE_UPDATE" = true ]) && [ -x "scripts/post-sync.sh" ]; then
        print_status "Running scripts/post-sync.sh..."
        if ! ./scripts/post-sync.sh; then
            print_error "scripts/post-sync.sh failed in $REPO"
            cd ..
            FAILED_REPOS="$FAILED_REPOS $REPO"
            echo ""
            continue
        fi
        if [ -n "$(git status --porcelain)" ] && $COMMIT_CHANGES; then
            git add -u
            git commit -m "post-sync: regenerate generated files for $BRANCH"
        fi
    fi

    # Push changes if requested (only if we made changes)
    if [ "$NEEDS_UPDATE" = true ] || [ "$NEEDS_SUBMODULE_UPDATE" = true ]; then
        if $PUSH_CHANGES; then
            print_status "Pushing to midstream/$BRANCH (force push)..."
            if git push midstream "$BRANCH" --force; then
                print_status "Successfully pushed to midstream"
            else
                print_error "Failed to push to midstream"
                FAILED_REPOS="$FAILED_REPOS $REPO"
            fi
        else
            print_warning "Skipping push (--no-push flag set)"
            print_status "To push manually later, run:"
            echo "  cd $REPO && git push midstream $BRANCH --force"
        fi
    fi

    cd ..
    echo ""
done

# Summary
echo "========================================="
print_status "Sync and rebase complete!"
echo ""
print_status "Summary:"
echo "  - Total repositories: $TOTAL_REPOS"
echo "  - Branch: $BRANCH"
echo "  - Commit changes: $COMMIT_CHANGES"
echo "  - Push changes: $PUSH_CHANGES"

# Count successful, skipped, and failed
SUCCESSFUL_COUNT=$((TOTAL_REPOS - $(echo "$FAILED_REPOS $SKIPPED_REPOS" | wc -w)))

if [ -n "$SKIPPED_REPOS" ]; then
    echo ""
    print_status "Skipped repositories (already up-to-date):"
    for REPO in $SKIPPED_REPOS; do
        echo "  - $REPO"
    done
fi

if [ -n "$FAILED_REPOS" ]; then
    echo ""
    print_error "Failed repositories:"
    for REPO in $FAILED_REPOS; do
        echo "  - $REPO"
    done
    exit 1
else
    echo ""
    print_status "Processed: $SUCCESSFUL_COUNT updated, $(echo "$SKIPPED_REPOS" | wc -w) skipped, 0 failed"
fi