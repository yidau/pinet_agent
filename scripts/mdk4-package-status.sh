#!/usr/bin/env bash
set -eu

if (( $# != 0 )); then
    echo 'Usage: mdk4-package-status' >&2
    exit 2
fi

# Query the package database only. The package executable is never invoked.
result=0
record=$(LC_ALL=C /usr/bin/dpkg-query -W -f='${db:Status-Status}|${Version}|${Architecture}' mdk4 2>/dev/null) || result=$?
if (( result == 1 )); then
    printf '%s\n' '{"status":"not_installed"}'
    exit 0
fi
if (( result == 0 )); then
    IFS='|' read -r status version architecture <<< "$record"
    case "$status" in
        installed)
            if [[ "$version" =~ ^[0-9][0-9A-Za-z.+:~-]*$ && "$architecture" =~ ^[a-z0-9-]+$ ]] &&
                [[ "$record" == "$status|$version|$architecture" ]]; then
                printf '{"status":"installed","version":"%s","architecture":"%s"}\n' "$version" "$architecture"
                exit 0
            fi
            ;;
        not-installed|config-files)
            printf '%s\n' '{"status":"not_installed"}'
            exit 0
            ;;
        half-installed|unpacked|half-configured|triggers-awaited|triggers-pending)
            printf '%s\n' '{"status":"incomplete"}'
            exit 0
            ;;
    esac
fi
printf '%s\n' '{"status":"unavailable"}'
exit 1
