alias tag := release

# Release a new version (defaults to today's date in YYYY.MM.DD.N format)
release TAG="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Use provided tag or auto-increment today's date
    if [[ -z "{{ TAG }}" ]]; then
        base_date=$(date +%Y.%m.%d)

        # Find existing tags for today and get the highest micro version
        existing_tags=$(git tag -l "${base_date}*" | sort -V)

        if [[ -z "$existing_tags" ]]; then
            # No tags for today, start with .0
            version="${base_date}.0"
        else
            # Get the last (highest) tag for today
            last_tag=$(echo "$existing_tags" | tail -n 1)

            # Extract micro version number (everything after the second dot)
            if [[ "$last_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.([0-9]+)$ ]]; then
                # Format: YYYY.MM.DD.N
                micro=${BASH_REMATCH[1]}
                next_micro=$((micro + 1))
                version="${base_date}.${next_micro}"
            elif [[ "$last_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                # Format: YYYY.MM.DD (old format without micro)
                version="${base_date}.1"
            else
                # Unknown format, start fresh
                version="${base_date}.0"
            fi
        fi
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

update:
    #!/usr/bin/env bash
    set -euo pipefail

    brew update
    brew upgrade pancake
