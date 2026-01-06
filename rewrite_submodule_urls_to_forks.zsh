#!/usr/bin/env zsh
set -euo pipefail

# Fork every submodule upstream and rewrite .gitmodules URLs to your forks.
#
# Requirements:
#   - gh authenticated: gh auth login
#   - run from repo root containing .gitmodules
#
# Optional env vars:
#   DRY_RUN=1            (default 0)
#   UPDATE_REMOTES=1     (default 1)
#   FORK_PREFIX=""       (optional prefix for fork-name)
#   FORK_NAME_STYLE=owner--repo|repo  (default owner--repo)

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

# Must be in a git repo root
git rev-parse --show-toplevel >/dev/null 2>&1 || die "Not inside a git repository."
TOP="$(git rev-parse --show-toplevel)"
cd "$TOP"

[[ -f .gitmodules ]] || die "No .gitmodules found at repo root: $TOP"

command -v gh >/dev/null 2>&1 || die "gh not found. Install GitHub CLI first."
gh auth status >/dev/null 2>&1 || die "gh not authenticated. Run: gh auth login"

GH_USER="$(gh api user -q .login 2>/dev/null || true)"
[[ -n "$GH_USER" ]] || die "Could not determine GitHub username via: gh api user -q .login"

print -r -- "Repo root      : $TOP"
print -r -- "GitHub user    : $GH_USER"
print -r -- "DRY_RUN        : $DRY_RUN"
print -r -- "UPDATE_REMOTES : $UPDATE_REMOTES"
print -r -- "FORK_PREFIX    : $FORK_PREFIX"
print -r -- "FORK_NAME_STYLE: $FORK_NAME_STYLE"
print -r -- ""

normalize_slug() {
    local url="$1"
    url="${url#git@github.com:}"
    url="${url#https://github.com/}"
    url="${url#https://www.github.com/}"
    url="${url%.git}"
    print -r -- "$url"
}

make_fork_name() {
    local upstream_owner="$1"
    local repo="$2"
    case "${FORK_NAME_STYLE:-owner--repo}" in
        owner--repo) print -r -- "${FORK_PREFIX}${upstream_owner}--${repo}" ;;
        repo)        print -r -- "${FORK_PREFIX}${repo}" ;;
        *)           die "Unsupported FORK_NAME_STYLE='${FORK_NAME_STYLE:-}' (use owner--repo or repo)" ;;
    esac
}

# Enumerate canonical keys directly (no parsing of values)
typeset -a PATH_KEYS
PATH_KEYS=("${(@f)$(git config -f .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)}")
(( ${#PATH_KEYS} > 0 )) || die ".gitmodules has no submodule.*.path entries."

print -r -- "Discovered ${#PATH_KEYS} submodule(s) in .gitmodules"
print -r -- ""

for k in "${PATH_KEYS[@]}"; do
    # k is: submodule.<name>.path
    local name sm_path upstream_url slug owner repo fork_name fork_url

    name="${k#submodule.}"
    name="${name%.path}"

    sm_path="$(git config -f .gitmodules --get "$k" 2>/dev/null || true)"
    upstream_url="$(git config -f .gitmodules --get "submodule.${name}.url" 2>/dev/null || true)"


    if [[ -z "$sm_path" ]]; then
        print -u2 -- "WARN: Missing path value for k '$k' (submodule '$name'); skipping."
        continue
    fi

    if [[ -z "$upstream_url" ]]; then
        print -u2 -- "WARN: Skipping submodule '$name' (path='$sm_path' url='')"
        continue
    fi

    slug="$(normalize_slug "$upstream_url")"
    owner="${slug%%/*}"
    repo="${slug##*/}"

    if [[ -z "$owner" || -z "$repo" || "$owner" == "$repo" ]]; then
        print -u2 -- "WARN: Couldnt parse owner/repo from url '$upstream_url' (submodule '$name', path '$sm_path'); skipping."
        continue
    fi

    fork_name="$(make_fork_name "$owner" "$repo")"
    fork_url="https://github.com/${GH_USER}/${fork_name}.git"

    print -r -- "== $sm_path =="
    print -r -- "  submodule name : $name"
    print -r -- "  upstream url   : $upstream_url"
    print -r -- "  upstream slug  : $owner/$repo"
    print -r -- "  fork name      : $fork_name"
    print -r -- "  fork url       : $fork_url"
    print -r -- ""

    if [[ "$DRY_RUN" == "1" ]]; then
        print -r -- "[dry-run] gh repo fork ${owner}/${repo} --clone=false --remote=false --fork-name ${fork_name}"
    else
        if ! gh repo fork "${owner}/${repo}" --clone=false --remote=false --fork-name "${fork_name}" >/dev/null 2>&1; then
            if ! gh repo view "${GH_USER}/${fork_name}" >/dev/null 2>&1; then
                print -u2 -- "WARN: Fork failed  and for repo not found: ${GH_USER}/${fork_name} (from ${owner}/${repo}); skipping"
                continue
            fi
        fi
    fi

    run git config -f .gitmodules "submodule.${name}.url" "$fork_url"

    if [[ "$UPDATE_REMOTES" == "1" && -d "$sm_path" && ( -f "$sm_path/.git" || -d "$sm_path/.git" ) ]]; then
        if [[ "$DRY_RUN" == "1" ]]; then
            print -r -- "[dry-run] (cd $sm_path && git remote set-url upstream '$upstream_url' || git remote add upstream '$upstream_url')"
            print -r -- "[dry-run] (cd $sm_path && git remote set-url origin '$fork_url' || git remote add origin '$fork_url')"
        else
            (
                cd "$sm_path"
                if git remote get-url upstream >/dev/null 2>&1; then
                    git remote set-url upstream "$upstream_url"
                else
                    git remote add upstream "$upstream_url" >/dev/null 2>&1 || true
                fi
                if git remote get-url origin >/dev/null 2>&1; then
                    git remote set-url origin "$fork_url"
                else
                    git remote add origin "$fork_url" >/dev/null 2>&1 || true
                fi
            )
        fi
    fi
done

run git add .gitmodules

print -r -- ""
print -r -- "Done rewriting .gitmodules."
print -r -- "Next steps:"
print -r -- "  git diff -- .gitmodules"
print -r -- "  git commit -m \"Rewrite submodule URLs to my forks\""
print -r -- "  git push"
print -r -- ""

