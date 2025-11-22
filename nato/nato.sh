#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [TEXT...]

Convert text to the NATO phonetic alphabet.

OPTIONS:
    -h, --help    Show this help message and exit

DESCRIPTION:
    Reads text from standard input or arguments and prints the corresponding
    NATO phonetic alphabet representation.

EXAMPLES:
    $ $0 hello world
    Hotel Echo Lima Lima Oscar · Whiskey Oscar Romeo Lima Delta

    $ echo "sos" | $0
    Sierra Oscar Sierra

EXIT CODES:
    0    Success
    1    Error
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

main() {
    local input

    if [[ $# -gt 0 ]]; then
        input="$*"
    else
        if [ -t 0 ]; then
            usage
            exit 1
        fi
        input=$(cat)
    fi

    # Convert to uppercase
    # shellcheck disable=SC2001
    input=$(echo "$input" | tr '[:lower:]' '[:upper:]')

    local len=${#input}
    for (( i=0; i<len; i++ )); do
        local char="${input:$i:1}"
        case "$char" in
            A) echo -n "Alfa " ;;
            B) echo -n "Bravo " ;;
            C) echo -n "Charlie " ;;
            D) echo -n "Delta " ;;
            E) echo -n "Echo " ;;
            F) echo -n "Foxtrot " ;;
            G) echo -n "Golf " ;;
            H) echo -n "Hotel " ;;
            I) echo -n "India " ;;
            J) echo -n "Juliett " ;;
            K) echo -n "Kilo " ;;
            L) echo -n "Lima " ;;
            M) echo -n "Mike " ;;
            N) echo -n "November " ;;
            O) echo -n "Oscar " ;;
            P) echo -n "Papa " ;;
            Q) echo -n "Quebec " ;;
            R) echo -n "Romeo " ;;
            S) echo -n "Sierra " ;;
            T) echo -n "Tango " ;;
            U) echo -n "Uniform " ;;
            V) echo -n "Victor " ;;
            W) echo -n "Whiskey " ;;
            X) echo -n "X-ray " ;;
            Y) echo -n "Yankee " ;;
            Z) echo -n "Zulu " ;;
            0) echo -n "Zero " ;;
            1) echo -n "One " ;;
            2) echo -n "Two " ;;
            3) echo -n "Three " ;;
            4) echo -n "Four " ;;
            5) echo -n "Five " ;;
            6) echo -n "Six " ;;
            7) echo -n "Seven " ;;
            8) echo -n "Eight " ;;
            9) echo -n "Nine " ;;
            " ") echo -n "· " ;;
            $'\n') echo "" ;;
            *) echo -n "$char " ;;
        esac
    done
    echo ""
}

main "$@"
