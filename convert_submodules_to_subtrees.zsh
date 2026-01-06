#!/usr/bin/env zsh
set -euo pipefail

# Converts all git submodules (from .gitmodules) into git subtrees at the same paths.
#
# Usage:
#   ./convert_submodules_to_subtrees.zsh
#
# Optional env vars:
#   SQUASH=1|0        (default 1)
#   DRY_RUN=1|0       (default 0)
#   KEEP_WORKTREE=1|0 (default 0)  # if 1, does not rm -rf the path after git rm --cached

SQUASH="${SQUASH:-1}"
DRY_RUN="${DRY_RUN:-0}"
KEEP_WORKTREE="${KEEP_WORKTREE:-0}"

run() {
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        print -r -- "[dry-run] $*"
    else
        "$@"
    fi
}

die() {
    print -r -- "ERROR: $*" >&2
    exit 1
}

git rev-parse --show-toplevel >/dev/null 2>&1 || die "Not inside a git repository."
TOP="$(git rev-parse --show-toplevel)"
cd "$TOP"

[[ -f .gitmodules ]] || die "No .gitmodules found at repo root ($TOP). Nothing to convert."

# Safety: require clean parent repo to avoid mixing unrelated changes with subtree commits
if ! git diff --quiet || ! git diff --cached --quiet; then
    die "Parent repo has uncommitted changes. Commit or stash them first, then rerun."
fi

detect_default_branch() {
    local url="$1"
    git ls-remote --symref "$url" HEAD 2>/dev/null \
        | awk '/^ref: refs\/heads\// {sub("refs/heads/","",$2); print $2; exit}'
}

# Enumerate canonical submodule path keys (no parsing of value output)
typeset -a PATH_KEYS
PATH_KEYS=("${(@f)$(git config -f .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)}")
(( ${#PATH_KEYS} > 0 )) || die ".gitmodules exists but contains no submodule.*.path entries."

# Build tab-separated list: "<depth>\t<length>\t<name>\t<sm_path>"
typeset -a ROWS
ROWS=()
for k in "${PATH_KEYS[@]}"; do
    local name sm_path depth len
    name="${k#submodule.}"
    name="${name%.path}"

    sm_path="$(git config -f .gitmodules --get "$k" 2>/dev/null || true)"
    [[ -n "$sm_path" ]] || die "Missing path value for key '$k' (submodule '$name')."

    # Compute depth (# of slashes)
    depth="${#${(s:/:)sm_path}}"
    (( depth = depth - 1 ))  # segments-1 = slash count
    len="${#sm_path}"

    ROWS+=("${depth}\t${len}\t${name}\t${sm_path}")
done

# Sort deepest-first, then longest-first (helps nested paths)
typeset -a ROWS_SORTED
ROWS_SORTED=("${(@f)$(print -r -- "${(j:\n:)ROWS}" | sort -t $'\t' -nr -k1,1 -k2,2)}")

print -r -- "Repository: $TOP"
print -r -- "Found ${#ROWS_SORTED} submodule(s) in .gitmodules"
print -r -- "SQUASH=$SQUASH DRY_RUN=$DRY_RUN KEEP_WORKTREE=$KEEP_WORKTREE"
print -r -- ""

for row in "${ROWS_SORTED[@]}"; do
    local _depth _len name sm_path url branch rc
    _depth="${row%%$'\t'*}"
    row="${row#*$'\t'}"
    _len="${row%%$'\t'*}"
    row="${row#*$'\t'}"
    name="${row%%$'\t'*}"
    sm_path="${row#*$'\t'}"

    url="$(git config -f .gitmodules --get "submodule.${name}.url" 2>/dev/null || true)"
    [[ -n "$url" ]] || die "Missing url for submodule '$name' (path '$sm_path') in .gitmodules."

    # If .gitmodules specifies a branch, use it; else detect default; else fallback.
    branch="$(git config -f .gitmodules --get "submodule.${name}.branch" 2>/dev/null || true)"
    if [[ -z "$branch" ]]; then
        branch="$(detect_default_branch "$url" || true)"
    fi
    [[ -n "$branch" ]] || branch="main"

    print -r -- "== Converting submodule =="
    print -r -- "name : $name"
    print -r -- "path : $sm_path"
    print -r -- "url  : $url"
    print -r -- "ref  : $branch"
    print -r -- ""

    # 1) Deinit submodule (removes per-submodule config association); tolerate already-deinit
    run git submodule deinit -f -- "$sm_path" || true

    # 2) Remove gitlink from index; tolerate if already removed
    run git rm -f --cached -- "$sm_path" || true

    # 3) Remove module gitdir metadata
    run rm -rf ".git/modules/$sm_path" || true

    # 4) Remove worktree dir (recommended to avoid subtree add collisions)
    if [[ "$KEEP_WORKTREE" != "1" ]]; then
        run rm -rf "$sm_path" || true
    fi

    # 5) Add subtree at same prefix
    if [[ "$DRY_RUN" == "1" ]]; then
        if [[ "$SQUASH" == "1" ]]; then
            print -r -- "[dry-run] git subtree add --prefix=$sm_path $url $branch --squash"
        else
            print -r -- "[dry-run] git subtree add --prefix=$sm_path $url $branch"
        fi
    else
        set +e
        if [[ "$SQUASH" == "1" ]]; then
            git subtree add --prefix="$sm_path" "$url" "$branch" --squash
            rc=$?
        else
            git subtree add --prefix="$sm_path" "$url" "$branch"
            rc=$?
        fi
        set -e

        if [[ $rc -ne 0 && "$branch" == "main" ]]; then
            print -r -- "Subtree add failed with branch 'main'. Trying 'master'..."
            if [[ "$SQUASH" == "1" ]]; then
                git subtree add --prefix="$sm_path" "$url" master --squash
            else
                git subtree add --prefix="$sm_path" "$url" master
            fi
        elif [[ $rc -ne 0 ]]; then
            die "Subtree add failed for '$sm_path' from '$url' ref '$branch'."
        fi
    fi

    print -r -- ""
done

# Remove .gitmodules after conversion
if [[ "$DRY_RUN" == "1" ]]; then
    print -r -- "[dry-run] rm -f .gitmodules"
else
    rm -f .gitmodules || true
    git add -A
fi

print -r -- ""
print -r -- "Conversion complete."
print -r -- "Next steps:"
print -r -- "  git status"
print -r -- "  git commit -m \"Convert submodules to subtrees\""
print -r -- "  git push"

# vim: set ft=zsh ts=8 sw=4 sts=4 tw=100
