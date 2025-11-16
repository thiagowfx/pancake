# pdf_password_remove.sh

Remove password protection from PDF files.

## Usage

```bash
# Interactive password prompt (most secure)
pdf_password_remove secret.pdf

# Process multiple files
pdf_password_remove report.pdf invoice.pdf contract.pdf

# Provide password via command line
pdf_password_remove --password=BANANA42SPLIT secret.pdf

# Custom output filename (single file only)
pdf_password_remove -o unlocked.pdf secret.pdf
```

## Example Output

```
% pdf_password_remove --password=PIZZA69SLICE financial-report.pdf tax-form.pdf
✓ Successfully processed: financial-report.pdf → financial-report-unlocked.pdf
✓ Successfully processed: tax-form.pdf → tax-form-unlocked.pdf

Summary: Successfully processed 2/2 file(s)
```

## Features

- Process single or multiple PDF files in one command
- Secure interactive password prompt (hidden input)
- Command-line password option for automation/scripts
- Default output naming: adds `-unlocked` suffix
- Custom output filename with `-o` flag (single file only)
- Clear success/failure indicators for each file
- Validates PDF files before processing

## Prerequisites

Requires either `ghostscript` (preferred) or `qpdf` to be installed:

```bash
# macOS
brew install ghostscript       # Preferred
brew install qpdf              # Alternative

# Linux
sudo apt install ghostscript   # Preferred - Debian/Ubuntu
sudo apt install qpdf          # Alternative

sudo dnf install ghostscript   # Preferred - Fedora
sudo dnf install qpdf          # Alternative

sudo pacman -S ghostscript     # Preferred - Arch
sudo pacman -S qpdf            # Alternative
```

The script automatically detects and uses whichever tool is available, preferring ghostscript if both are installed.

## Security Note

Using `--password` on the command line will expose the password in shell history and process lists. For sensitive documents, use the interactive prompt instead (default behavior when password is not provided).
