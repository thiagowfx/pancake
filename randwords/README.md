# randwords

Generate random word combinations similar to Docker container names and DuckDuckGo disposable email addresses.

Perfect for naming containers, projects, or generating memorable disposable identifiers.

## Features

- **Docker-style naming**: Alternates adjectives and nouns (e.g., `happy-dolphin`)
- **Random-style**: Pure random word selection from dictionary
- **Configurable separators**: Use hyphens, underscores, or any single character
- **Number suffixes**: Optional random number generation
- **Capitalization**: Capitalize first letters for title case output
- **Word length filtering**: Control minimum and maximum word lengths
- **Batch generation**: Generate multiple outputs at once
- **Embedded wordlists**: No external dependencies - wordlists built into the script

## Usage

```bash
randwords [OPTIONS]
```

## Options

- `-n, --num NUM` - Number of words to generate (default: 2)
- `-s, --separator CHAR` - Word separator (default: `-`)
- `-N, --number` - Append random number suffix (1-9999)
- `-c, --capitalize` - Capitalize first letter of each word
- `-l, --min-len NUM` - Minimum word length (default: 4)
- `-L, --max-len NUM` - Maximum word length (default: 10)
- `-r, --repeat NUM` - Generate multiple outputs (default: 1)
- `-t, --type TYPE` - Word style: `docker` or `random` (default: docker)
- `-h, --help` - Show help message

## Examples

Generate basic random names:
```bash
randwords
# Output: happy-dolphin
```

Generate three words:
```bash
randwords -n 3
# Output: happy-dolphin-brave
```

Use custom separator:
```bash
randwords -s _
# Output: happy_dolphin
```

Add random number suffix:
```bash
randwords -N
# Output: happy-dolphin-42
```

Capitalize first letters:
```bash
randwords -c -n 3 -N
# Output: Happy-Dolphin-Brave-42
```

Generate multiple outputs:
```bash
randwords -r 3
# Output:
# happy-dolphin
# brave-tiger
# swift-falcon
```

Use random word style:
```bash
randwords -t random -n 3
# Output: random words from dictionary
```

Constrain word lengths:
```bash
randwords --min-len 3 --max-len 8
# Output: joy-fun-sky
```

Docker-style with four words:
```bash
randwords -t docker -n 4
# Output: happy-dolphin-brave-tiger
```

## Word Styles

### Docker Style (default)

Alternates adjectives and nouns for memorable combinations:

- 2 words: `adjective-noun` (e.g., `happy-dolphin`)
- 3 words: `adjective-noun-adjective` (e.g., `happy-dolphin-brave`)
- 4 words: `adjective-noun-adjective-noun` (e.g., `happy-dolphin-brave-tiger`)

### Random Style

Selects words randomly without pattern enforcement:

```bash
randwords -t random -n 3
# Output: any-combination-of-words
```

## Output Format

- Single output: Prints result to stdout
- Multiple outputs (`-r`): One result per line
- All outputs are suitable for use as identifiers (no spaces, special characters, or apostrophes)

## Prerequisites

None. The script includes embedded wordlists - no external dependencies.

## Common Use Cases

**Container naming:**
```bash
docker run --name $(randwords) nginx
```

**Project directory naming:**
```bash
mkdir "$(randwords -c)"
# Output: Happy-Dolphin
```

**Disposable email generation:**
```bash
echo "$(randwords)@example.com"
# Output: happy-dolphin-42@example.com
```

**Batch name generation:**
```bash
for i in $(randwords -r 5); do
    echo "Creating container: $i"
done
```

**Password-adjacent memorable strings:**
```bash
randwords -n 3 -s '' -N -c
# Output: HappyDolphinBrave1234
```
