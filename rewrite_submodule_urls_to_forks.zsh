#!/usr/bin/env zsh
set -euo pipefail

# Fork every submodule upstream and rewrite .gitmodules URLs to your forks.
# Requirements:
#   - gh authenticated: gh auth login
#   - run from the parent repo root (where .gitmodules lives)
#
# Optional env vars:
#   DRY_RUN=1   (prints actions, doesnt change anything)
#   UPDATE_REMOTES=1 (default 1) (Updates each checked-out submodule's origin/upstream remotes)
#   FORK_PREFIX=""  (optional prefix for fork-name, e.g. "tn--")

DRY_RUN="${DRY_RUN:-0}"
UPDATE_REMOTES="${UPDATE_REMOTES:-1}"
FORK_PREFIX="${FORK_PREFIX:-}"
FORK_NAME_STYLE="${FORK_NAME_STYLE:-owner--repo}"

run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        print -r -- "[dry-run] $*"
    else
        "$@"
    fi
}

die() {
    print -r -- "ERROR: $*" >&2
    exit 1
}

# Must be in git repo root.
git rev-parse --show-toplevel >/dev/null 2>&1 || die "Not inside a git repository."
TOP="$(git rev-parse --show-toplevel)"
cd "$TOP"

[[ -f .gitmodules ]] || die "No .gitmodules found at repo root ($TOP). Nothing to convert."

# Ensure gh is available and authenticated
command -v gh >/dev/null 2>&1 || die "gh not found. Install gh cli first."
gh auth status >/dev/null 2>&1 || die "gh not authenticated. Run: gh auth login."

GH_USER="$(gh api user -q .login 2>/dev/null || true)"
[[ -n "$GH_USER" ]] || die "Couldnt determine GitHub username via: gh api -q .login"

print -r -- "Repo root      : $TOP"
print -r -- "GitHub user    : $GH_USER"
print -r -- "DRY_RUN        : $DRY_RUN"
print -r -- "UPDATE_REMOTES : $UPDATE_REMOTES"
print -r -- "FORK_PREFIX    : $FORK_PREFIX"
print -r -- "FORK_NAME_STYLE: $FORK_NAME_STYLE"
print -r -- ""

# Helper: normalize URL -> owner/repo (strip protocol, git@, .git)
# Accepts:
#   https://github.com/OWNER/REPO.git
#   https://github.com/OWNER/REPO
#   git@github.com:OWNER/REPO.git
normalize_slug() {
    local url="$1"
    url="${url#git@github.com:}"
    url="${url#https://github.com/}"
    url="${url#https://www.github.com/}"
    url="${url%.git}"
    print -r -- "$url"
}

# Helper: choose fork name with collision-avoidance
make_fork_name() {
    local upstream_owner="$1"
    local repo="$2"
    case "$FORK_NAME_STYLE" in
        owner-repo)
            print -r -- "${FORK_PREFIX}${upstream_owner}--${repo}"
            ;;
        repo)
            print -r -- "${FORK_PREFIX}${repo}"
            ;;
        *)
            die "Unsupported FORK_NAME_STYLE='$FORK_NAME_STYLE' (use owner--repo or repo)"
            ;;
    esac
}

# --- Robust enumeration: do NOT parse "git config --get-regexp" lines ---
typeset -a SUB_KEYS SUB_NAMES
SUB_KEYS=("${(@f)$(git config -f .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)}")
(( ${#SUB_KEYS} > 0 )) || die ".gitmodules has no submodule.*.path entries."

SUB_NAMES=()
for k in "${SUB_KEYS[@]}"; do
    # k like: submodule.PythonDataScienceHandbook.path
    local n="${k#submodule.}"
    n="${n%.path}"
    [[ -n "$n" ]] || die "Failed to parse submodule name from key: $k"
    SUB_NAMES+=("$n")
done

# Deduplicate names (defensive)
SUB_NAMES=("${(@u)SUB_NAMES}")

print -r -- "Discovered ${#SUB_NAMES} submodule(s) in .gitmodules"
print -r -- ""

for name in "${SUB_NAMES[@]}"; do
    local path upstream_url slug owner repo fork_name fork_url

    path="$(git config -f .gitmodules --get "submodule.${name}.path" 2>/dev/null || true)"
    upstream_url="$(git config -f .gitmodules --get "submodule.${name}.url" 2>/dev/null || true)"

    [[ -n "$path" ]] || die "Missing path for submodule '$name' in .gitmodules."
    [[ -n "$upstream_url" ]] || die "Missing url for submodule '$name' (path '$path')."

    slug="$(normalize_slug "$upstream_url")"
    owner="${slug%%/*}"
    repo="${slug##*/}"

    [[ -n "$owner" && -n "$repo" && "$owner" != "$repo" ]] || die "Could not parse owner/repo from url: $upstream_url"

    fork_name="$(make_fork_name "$owner" "$repo")"
    fork_url="https://github.com/${GH_USER}/${fork_name}.git"

    print -r -- "== $path =="
    print -r -- "  submodule name : $name"
    print -r -- "  upstream url   : $upstream_url"
    print -r -- "  upstream slug  : $owner/$repo"
    print -r -- "  fork name      : $fork_name"
    print -r -- "  fork url       : $fork_url"
    print -r -- ""

    # 1) Fork upstream into your account (idempotent)
    if [[ "$DRY_RUN" == "1" ]]; then
        print -r -- "[dry-run] gh repo fork ${owner}/${repo} --clone=false --remote=false --fork-name ${fork_name}"
    else
        if ! gh repo fork "${owner}/${repo}" --clone=false --remote=false --fork-name "${fork_name}" >/dev/null 2>&1; then
            # gh may error if fork already exists; verify existence and proceed
            if ! gh repo view "${GH_USER}/${fork_name}" >/dev/null 2>&1; then
                die "Fork failed and fork repo not found: ${GH_USER}/${fork_name} (from ${owner}/${repo})"
            fi
        fi
    fi

    # 2) Rewrite .gitmodules URL to point at your fork
    run git config -f .gitmodules "submodule.${name}.url" "$fork_url"

    # 3) Optionally update local submodule remotes (if submodule checkout exists)
    # Handles both submodule layouts:
    #   - $path/.git is a file pointing to gitdir
    #   - $path/.git is a directory
    if [[ "$UPDATE_REMOTES" == "1" && -d "$path" && ( -f "$path/.git" || -d "$path/.git" ) ]]; then
        if [[ "$DRY_RUN" == "1" ]]; then
            print -r -- "[dry-run] (cd $path && git remote set-url upstream '$upstream_url' || git remote add upstream '$upstream_url')"
            print -r -- "[dry-run] (cd $path && git remote set-url origin '$fork_url' || git remote add origin '$fork_url')"
        else
            (
                cd "$path"

                # upstream -> original upstream URL
                if git remote get-url upstream >/dev/null 2>&1; then
                    git remote set-url upstream "$upstream_url"
                else
                    git remote add upstream "$upstream_url" >/dev/null 2>&1 || true
                fi

                # origin -> fork URL (so git push works)
                if git remote get-url origin >/dev/null 2>&1; then
                    git remote set-url origin "$fork_url"
                else
                    git remote add origin "$fork_url" >/dev/null 2>&1 || true
                fi
            )
        fi
    fi
done

# Stage .gitmodules changes
run git add .gitmodules

print -r -- ""
print -r -- "Done rewriting .gitmodules."
print -r -- "Next steps:"
print -r -- "  git diff -- .gitmodules"
print -r -- "  git commit -m \"Rewrite submodule URLs to my forks\""
print -r -- "  git push"
print -r -- ""
print -r -- "Tip: if you plan to convert to subtrees next, rewrite URLs first so subtree import can target forks you control."


# vim: set ft=zsh ts=8 sw=4 sts=4 tw=100
