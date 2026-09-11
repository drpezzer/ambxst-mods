#!/usr/bin/env bash
# Mod Updater: report the latest available version of installed Ambxst mods.
#
# Each argument is one installed mod as "id<TAB>sourceType<TAB>source".
# Prints one line per argument: "id<TAB><version>" or "id<TAB>ERR:<reason>".
#   local       reads ambxst.mod.json from the source directory
#   git         fetches origin in the package clone and reads the manifest there
#   git-subdir  fetches the manifest straight from raw.githubusercontent.com
#   archive     cannot be checked (no remote to ask)
set -u
PACKAGES="${AMBXST_MOD_PACKAGES:-$HOME/.local/share/ambxst/mods/packages}"

manifest_version() {
    grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/'
}

for entry in "$@"; do
    IFS=$'\t' read -r id stype source <<<"$entry"
    [ -z "${id:-}" ] && continue
    version=""
    err=""
    case "${stype:-}" in
        local)
            if [ -f "$source/ambxst.mod.json" ]; then
                version=$(manifest_version < "$source/ambxst.mod.json")
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
                if body=$(timeout 25 curl -fsSL --retry 1 "$url" 2>/dev/null); then
                    version=$(manifest_version <<<"$body")
                else
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
                version=""
                first=""
                while IFS= read -r path; do
                    body=$(git -C "$dir" show "FETCH_HEAD:$path" 2>/dev/null) || continue
                    [ -z "$first" ] && first=$body
                    if grep -qE "\"id\"[[:space:]]*:[[:space:]]*\"$id\"" <<<"$body"; then
                        version=$(manifest_version <<<"$body")
                        break
                    fi
                done < <(git -C "$dir" ls-tree -r --name-only FETCH_HEAD 2>/dev/null | grep -E '(^|/)ambxst\.mod\.json$')
                if [ -z "$version" ] && [ -n "$first" ]; then
                    version=$(manifest_version <<<"$first")
                fi
                [ -z "$version" ] && err="remote has no ambxst.mod.json"
            fi
            ;;
        archive)
            err="archive sources cannot be checked"
            ;;
        *)
            err="unknown source type"
            ;;
    esac
    if [ -n "$err" ]; then
        printf '%s\tERR:%s\n' "$id" "$err"
    elif [ -z "$version" ]; then
        printf '%s\tERR:%s\n' "$id" "manifest has no version"
    else
        printf '%s\t%s\n' "$id" "$version"
    fi
done
