#!/bin/sh
set -eu

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    printf 'Usage: %s "commit message"\n' "$0" >&2
    exit 2
fi

if [ "$(git symbolic-ref --quiet --short HEAD)" != main ]; then
    printf 'Switch to the main branch before publishing.\n' >&2
    exit 1
fi

git commit -m "$1"
git push origin main
