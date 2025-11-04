alias tag := release

# Release a new version (defaults to today's date in YYYY.MM.DD format)
release TAG="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Use provided tag or default to today's date
    if [[ -z "{{ TAG }}" ]]; then
        version=$(date +%Y.%m.%d)
    else
        version="{{ TAG }}"
    fi

    echo "Creating release ${version}..."

    # Check if tag already exists
    if git rev-parse "${version}" >/dev/null 2>&1; then
        echo "Error: Tag ${version} already exists"
        exit 1
    fi

    # Create and push tag
    git tag "${version}"
    git push origin "${version}"

    echo "✓ Tag ${version} created and pushed"
    echo "✓ GitHub Actions will update the formula automatically"
    echo ""
    echo "Monitor the workflow at:"
    echo "https://github.com/thiagowfx/pancake/actions/workflows/release.yml"
