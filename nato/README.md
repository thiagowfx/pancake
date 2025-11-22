# nato.sh

Convert text to the NATO phonetic alphabet.

## Usage

Pass text as arguments:

```bash
./nato.sh hello world
```

Or pipe text via stdin:

```bash
echo "sos" | ./nato.sh
```

## Example Output

```
% ./nato.sh hello world
Hotel Echo Lima Lima Oscar · Whiskey Oscar Romeo Lima Delta
```

```
% echo "sos" | ./nato.sh
Sierra Oscar Sierra
```
