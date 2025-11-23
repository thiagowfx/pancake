#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] [PORT]

Start a local HTTP server in the current directory.

Start a simple HTTP server in the current directory. The script automatically
detects and uses the first available tool from: Python 3, Python, Perl, or
Ruby. The server will be accessible at http://localhost:PORT

ARGUMENTS:
    PORT          Port to listen on (default: 8000)

OPTIONS:
    -h, --help    Show this help message and exit

EXAMPLES:
    $cmd              Start server on port 8000
    $cmd 3000         Start server on port 3000
    $cmd --help       Show this help

EXIT CODES:
    0    Server started successfully
    1    No suitable HTTP server tool found
EOF
}

main() {
    local port=8000

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            *)
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    port="$1"
                else
                    echo "Error: Invalid port number: $1" >&2
                    echo "Run '$0 --help' for usage information." >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    echo "Starting HTTP server on port $port..."
    echo "Serving directory: $(pwd)"
    echo "Access at: http://localhost:$port"
    echo ""

    if command -v python3 &>/dev/null; then
        echo "Using Python 3 http.server"
        exec python3 -m http.server "$port"
    elif command -v python &>/dev/null; then
        local python_version
        python_version="$(python -c 'import sys; print(sys.version_info[0])')"
        if [[ "$python_version" == "3" ]]; then
            echo "Using Python 3 http.server"
            exec python -m http.server "$port"
        else
            echo "Using Python 2 SimpleHTTPServer"
            exec python -m SimpleHTTPServer "$port"
        fi
    elif command -v perl &>/dev/null; then
        echo "Using Perl HTTP::Server::Brick"
        exec perl -MHTTP::Server::Brick -e "\$s=HTTP::Server::Brick->new(port=>$port); \$s->mount('/'=>{path=>'.'}); \$s->start"
    elif command -v ruby &>/dev/null; then
        echo "Using Ruby WEBrick server"
        exec ruby -run -e httpd . -p "$port"
    else
        echo "Error: No suitable HTTP server found" >&2
        echo "Install one of: python3, python, perl, or ruby" >&2
        exit 1
    fi
}

main "$@"
