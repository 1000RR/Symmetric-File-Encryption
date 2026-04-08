#!/usr/bin/env bash
# Bash-native only. No re-exec into any other shell.
# Name: shred-file.sh

set -u

red() {
    printf '\033[31m%s\033[0m\n' "$*"
}

green() {
    printf '\033[32m%s\033[0m\n' "$*"
}

red_prompt() {
    printf '\033[31m%s\033[0m' "$*"
}

die() {
    red "$*"
    exit 1
}

abs_path() {
    local input dir base

    input=$1
    dir=$(dirname "$input") || return 1
    base=$(basename "$input") || return 1

    (
        cd "$dir" 2>/dev/null &&
        printf '%s/%s\n' "$(pwd -P 2>/dev/null || pwd)" "$base"
    ) || return 1
}

is_dangerous_path() {
    case $1 in
        ''|/|.|..)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

get_file_size_bytes() {
    local f size
    f=$1

    [ -f "$f" ] || return 1

    size=$(wc -c < "$f" 2>/dev/null) || return 1
    size=${size//[!0-9]/}

    case $size in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    printf '%s\n' "$size"
}

shred_regular_file() {
    local f size bs count

    f=$1

    [ -e "$f" ] || return 0
    [ -f "$f" ] || return 0

    if [ -L "$f" ]; then
        red "Skipping symlink: $f"
        return 0
    fi

    [ -w "$f" ] || die "File is not writable: $f"
    [ -r /dev/urandom ] || die "/dev/urandom is not readable."

    size=$(get_file_size_bytes "$f") || die "Could not determine file size: $f"

    if [ "$size" -eq 0 ] 2>/dev/null; then
        rm -f "$f" || die "Failed to remove zero-length file: $f"
        green "shredded $f with size $size bytes"
        return 0
    fi

    bs=4096
    count=$(( (size + bs - 1) / bs ))

    dd if=/dev/urandom of="$f" bs="$bs" count="$count" conv=notrunc 2>/dev/null \
        || die "dd failed: $f"

    rm -f "$f" || die "rm failed: $f"

    green "shredded $f with size $size bytes"
}

shred_target() {
    local target path

    target=$1

    if [ -L "$target" ]; then
        die "Refusing symlink path: $target"
    fi

    if [ -f "$target" ]; then
        shred_regular_file "$target"
        return 0
    fi

    if [ -d "$target" ]; then
        command -v find >/dev/null 2>&1 || die "find is required for directory shredding."

        find "$target" -depth -print0 2>/dev/null |
        while IFS= read -r -d '' path; do
            if [ -L "$path" ]; then
                red "Skipping symlink: $path"
            elif [ -f "$path" ]; then
                shred_regular_file "$path"
            elif [ -d "$path" ]; then
                rmdir "$path" 2>/dev/null || true
            else
                red "Skipping non-regular, non-directory path: $path"
            fi
        done

        return 0
    fi

    die "Unsupported path type: $target"
}

main() {
    local input target answer

    if [ "$#" -ne 1 ]; then
        die "Usage: $0 <file-or-directory>"
    fi

    input=$1

    is_dangerous_path "$input" && die "Refusing dangerous path: $input"

    target=$(abs_path "$input") || die "Could not resolve path."
    is_dangerous_path "$target" && die "Refusing dangerous path: $target"

    [ -e "$target" ] || die "Path does not exist: $target"

    red_prompt "DO YOU WANT TO SHRED $target? "
    IFS= read -r answer || exit 1

    case $answer in
        yes|YES)
            ;;
        no|NO)
            exit 0
            ;;
        *)
            exit 0
            ;;
    esac

    shred_target "$target"

    if [ -e "$target" ]; then
        red "WARNING: $target still exists (likely due to skipped symlinks, special files, or non-empty directories)."
        exit 1
    fi

    red "$target shredded"
}

main "$@"