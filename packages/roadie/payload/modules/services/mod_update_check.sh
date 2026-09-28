#!/usr/bin/env bash
# Ambxst Roadie: report the latest available version of installed Ambxst mods,
# and the Ambxst version each of those needs.
#
# Each argument is one installed mod as "id<TAB>sourceType<TAB>source".
# Prints one line per argument:
#     id<TAB><version><TAB><ambxst range>      (range may be empty)
#     id<TAB>ERR:<reason>
# and, when it can be read, the Ambxst version an update would bring:
#     @ambxst<TAB><version>
#
#   local       reads ambxst.mod.json from the source directory
#   git         fetches origin in the package clone and reads the manifest there
#   git-subdir  fetches the manifest straight from raw.githubusercontent.com
#   archive     cannot be checked (no remote to ask)
set -u
PACKAGES="${AMBXST_MOD_PACKAGES:-${XDG_DATA_HOME:-$HOME/.local/share}/ambxst/mods/packages}"
AMBXST_VERSION_URL="${AMBXST_VERSION_URL:-https://raw.githubusercontent.com/Axenide/Ambxst/main/version}"

manifest_version() {
    grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/'
}

# compatibility.ambxst, e.g. ">=1.3.9 <2.0.0". "ambxst" is a key nowhere else
# in a manifest.
manifest_range() {
    grep -oE '"ambxst"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/' | tr '\t' ' '
}

for entry in "$@"; do
    IFS=$'\t' read -r id stype source <<<"$entry"
    [ -z "${id:-}" ] && continue
    body=""
    err=""
    case "${stype:-}" in
        local)
            if [ -f "$source/ambxst.mod.json" ]; then
                body=$(cat "$source/ambxst.mod.json")
            else
                err="source directory has no ambxst.mod.json"
            fi
            ;;
        git-subdir)
            rest=${source#https://github.com/}
            rest=${rest#http://github.com/}
            rest=${rest%/}
            owner=${rest%%/*}; rest=${rest#*/}
            repo=${rest%%/*};  rest=${rest#*/}
            repo=${repo%.git}
            if [ "${rest%%/*}" != "tree" ]; then
                err="unsupported source URL"
            else
                rest=${rest#tree/}
                ref=${rest%%/*}; sub=${rest#*/}
                url="https://raw.githubusercontent.com/$owner/$repo/$ref/$sub/ambxst.mod.json"
                if ! body=$(timeout 25 curl -fsSL --retry 1 "$url" 2>/dev/null); then
                    body=""
                    err="could not fetch manifest"
                fi
            fi
            ;;
        git)
            dir="$PACKAGES/$id"
            if [ ! -d "$dir/.git" ]; then
                err="package clone not found"
            elif ! timeout 60 git -C "$dir" fetch -q origin 2>/dev/null; then
                err="git fetch failed"
            else
                # A clone may hold several packages; take the manifest whose id
                # is this mod's, falling back to the first one found.
                first=""
                while IFS= read -r path; do
                    candidate=$(git -C "$dir" show "FETCH_HEAD:$path" 2>/dev/null) || continue
                    [ -z "$first" ] && first=$candidate
                    if grep -qE "\"id\"[[:space:]]*:[[:space:]]*\"$id\"" <<<"$candidate"; then
                        body=$candidate
                        break
                    fi
                done < <(git -C "$dir" ls-tree -r --name-only FETCH_HEAD 2>/dev/null | grep -E '(^|/)ambxst\.mod\.json$')
                [ -z "$body" ] && body=$first
                [ -z "$body" ] && err="remote has no ambxst.mod.json"
            fi
            ;;
        archive)
            err="archive sources cannot be checked"
            ;;
        *)
            err="unknown source type"
            ;;
    esac
    version=""
    range=""
    if [ -z "$err" ]; then
        version=$(manifest_version <<<"$body")
        range=$(manifest_range <<<"$body")
    fi
    if [ -n "$err" ]; then
        printf '%s\tERR:%s\n' "$id" "$err"
    elif [ -z "$version" ]; then
        printf '%s\tERR:%s\n' "$id" "manifest has no version"
    else
        printf '%s\t%s\t%s\n' "$id" "$version" "$range"
    fi
done

# The Ambxst version `ambxst update` would install. Best effort: without it
# the panel still says which Ambxst a mod needs, only not whether it is out.
if [ -n "$AMBXST_VERSION_URL" ]; then
    case "$AMBXST_VERSION_URL" in
        /*) latest=$(head -1 "$AMBXST_VERSION_URL" 2>/dev/null) ;;
        *)  latest=$(timeout 15 curl -fsSL --retry 1 "$AMBXST_VERSION_URL" 2>/dev/null | head -1) ;;
    esac
    latest=$(printf '%s' "${latest:-}" | tr -d '[:space:]')
    if [[ "$latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        printf '@ambxst\t%s\n' "$latest"
    fi
fi
