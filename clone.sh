#!/bin/bash

# Repository Cloning and Configuration Script
# This script clones all upstream repositories and configures them with midstream remotes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if repos.yaml exists
if [ ! -f "repos.yaml" ]; then
    print_error "repos.yaml not found in current directory"
    exit 1
fi

# Parse configuration from repos.yaml
UPSTREAM_ORG=$(grep "^upstream_org:" repos.yaml | awk '{print $2}')
MIDSTREAM_ORG=$(grep "^midstream_org:" repos.yaml | awk '{print $2}')
MIDSTREAM_PREFIX=$(grep "^midstream_prefix:" repos.yaml | awk '{print $2}')
BRANCH=$(grep "^branch:" repos.yaml | awk '{print $2}')

if [ -z "$UPSTREAM_ORG" ] || [ -z "$MIDSTREAM_ORG" ] || [ -z "$MIDSTREAM_PREFIX" ] || [ -z "$BRANCH" ]; then
    print_error "Failed to parse configuration from repos.yaml"
    exit 1
fi

# Optional per-user identity overrides (config.yaml)
# If config.yaml is absent or a value is unset, the existing git config is used.
GIT_EMAIL=""
SSH_KEY=""
if [ -f "config.yaml" ]; then
    GIT_EMAIL=$(grep "^git_email:" config.yaml | awk '{print $2}')
    SSH_KEY=$(grep "^ssh_key:" config.yaml | awk '{print $2}')
fi

print_status "Configuration loaded:"
print_status "  Upstream org: $UPSTREAM_ORG"
print_status "  Midstream org: $MIDSTREAM_ORG"
print_status "  Midstream prefix: $MIDSTREAM_PREFIX"
print_status "  Branch: $BRANCH"
print_status "  Git email: ${GIT_EMAIL:-(existing git config)}"
print_status "  SSH key: ${SSH_KEY:-(default SSH)}"
echo ""

# Extract repository list from repos.yaml
# This assumes repos are listed with "- " prefix after "repos:" line
REPOS=$(awk '/^repos:/{flag=1; next} /^[^-]/{flag=0} flag && /^- /{print $2}' repos.yaml)

if [ -z "$REPOS" ]; then
    print_error "No repositories found in repos.yaml"
    exit 1
fi

# Count total repositories
TOTAL_REPOS=$(echo "$REPOS" | wc -l)
CURRENT=0

print_status "Found $TOTAL_REPOS repositories to process"
echo ""

# Process each repository
for REPO in $REPOS; do
    CURRENT=$((CURRENT + 1))
    echo "[$CURRENT/$TOTAL_REPOS] Processing: $REPO"
    echo "----------------------------------------"

    UPSTREAM_URL="git@github.com:${UPSTREAM_ORG}/${REPO}.git"
    MIDSTREAM_URL="git@github.com:${MIDSTREAM_ORG}/${MIDSTREAM_PREFIX}${REPO}.git"

    # Check if repository directory exists
    if [ -d "$REPO" ]; then
        print_warning "Directory $REPO already exists, updating configuration..."
        cd "$REPO"

        # Check if it's a git repository
        if [ ! -d ".git" ]; then
            print_error "$REPO exists but is not a git repository"
            cd ..
            continue
        fi

        # Fetch latest from origin
        print_status "Fetching latest from upstream..."
        git fetch origin

    else
        # Clone the repository
        print_status "Cloning from $UPSTREAM_URL..."
        if ! git clone "$UPSTREAM_URL" "$REPO"; then
            print_error "Failed to clone $REPO"
            continue
        fi
        cd "$REPO"
    fi

    # Configure git user email (only if set in config.yaml)
    if [ -n "$GIT_EMAIL" ]; then
        print_status "Configuring git user email: $GIT_EMAIL"
        git config user.email "$GIT_EMAIL"
    else
        print_status "Using existing git user.email: $(git config user.email 2>/dev/null || echo '(global default)')"
    fi

    # Configure SSH command (only if set in config.yaml)
    if [ -n "$SSH_KEY" ]; then
        print_status "Configuring SSH key: $SSH_KEY"
        git config core.sshCommand "ssh -i $SSH_KEY -o IdentitiesOnly=yes"
    else
        print_status "Using default SSH configuration"
    fi

    # Register the `ours` merge driver so `.gitattributes merge=ours` actually
    # takes effect on this clone (git ships the strategy but not the per-file
    # driver). Used by overlays whose generated content is regenerated post-sync.
    git config merge.ours.driver true

    # Check if midstream remote exists
    if git remote | grep -q "^midstream$"; then
        print_status "Midstream remote already exists, updating URL..."
        git remote set-url midstream "$MIDSTREAM_URL"
    else
        print_status "Adding midstream remote: $MIDSTREAM_URL"
        git remote add midstream "$MIDSTREAM_URL"
    fi

    # Fetch from midstream remote
    print_status "Fetching from midstream remote..."
    if git fetch midstream 2>/dev/null; then
        print_status "Successfully fetched from midstream"
    else
        print_warning "Could not fetch from midstream (repository might not exist yet)"
    fi

    # Check out the target branch if it exists
    if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
        print_status "Checking out branch: $BRANCH"
        git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
    else
        print_warning "Branch $BRANCH does not exist in upstream"
    fi

    # Display current remotes
    print_status "Current remotes:"
    git remote -v | sed 's/^/  /'

    cd ..
    echo ""
done

print_status "Repository cloning and configuration complete!"
print_status "Summary:"
echo "  - Processed $TOTAL_REPOS repositories"
echo "  - Upstream remote: origin (github.com/$UPSTREAM_ORG)"
echo "  - Midstream remote: midstream (github.com/$MIDSTREAM_ORG)"
echo "  - Git user.email: ${GIT_EMAIL:-(existing git config)}"
echo "  - SSH key: ${SSH_KEY:-(default SSH)}"