# ocr

Extract text from images using optical character recognition.

## Usage

```bash
ocr image.png
ocr screenshot.jpg > extracted.txt
ocr receipt.png | pbcopy
ocr page1.png page2.png page3.png
find . -name "*.png" | xargs ocr
```

## Description

This script performs OCR on image files using Apple's Vision framework. It automatically detects the language, applies language correction, and uses accurate recognition settings for optimal text extraction.

The extracted text is printed to standard output, one line per recognized text block. When processing multiple files, output from each file is separated by a blank line.

## Prerequisites

- macOS 10.15 (Catalina) or later
- Swift (comes with Xcode or Command Line Tools)

## Options

- `-h, --help` - Show usage information

## Examples

Extract text from a screenshot:
```bash
ocr screenshot.png
```

Save extracted text to a file:
```bash
ocr document.jpg > document.txt
```

Copy extracted text to clipboard:
```bash
ocr receipt.png | pbcopy
```

Process multiple files:
```bash
ocr page1.png page2.png page3.png > combined.txt
```

Process all PNG files in a directory:
```bash
find . -name "*.png" | xargs ocr
```

## Exit Codes

- `0` - Text extracted successfully
- `1` - Invalid arguments, missing dependencies, or OCR failed

## Notes

- Works with common image formats: JPG, PNG, HEIC, etc.
- Supports automatic language detection
- Uses accurate recognition mode for best quality
- macOS-only (requires Vision framework)
