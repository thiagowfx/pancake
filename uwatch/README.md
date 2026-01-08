# uwatch

Run a command repeatedly using `watch`, preserving colored output.

Uses `unbuffer` to maintain color codes through `watch`'s output. Useful for monitoring git status, test output, or any command with color formatting.

## Installation

Available via Homebrew:

```bash
brew install thiagowfx/pancake/pancake
```

## Usage

```bash
uwatch [WATCH_OPTIONS] [--] COMMAND [ARGS...]
```

The `--` separator is optional. Watch options are automatically recognized.

### Examples

Watch git status with colors every 2 seconds:

```bash
uwatch git st
```

Watch git status with 1 second interval:

```bash
uwatch -n 1 git st
```

Watch test output with 5 second interval:

```bash
uwatch -n 5 npm test
```

### Dependencies

- `watch` - Part of procps-ng
- `unbuffer` - Part of expect package

On Alpine:
```bash
apk add procps expect
```

On macOS (via Homebrew):
```bash
brew install watch expect
```
