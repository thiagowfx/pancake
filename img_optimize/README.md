# img_optimize.sh

Optimize images for size while maintaining quality.

## Usage

Optimize a single image:

```bash
./img_optimize.sh photo.jpg
```

Optimize all images in a directory:

```bash
./img_optimize.sh vacation-photos/
```

Optimize with custom quality:

```bash
./img_optimize.sh --quality 90 cat-meme.png
```

Mix files and directories:

```bash
./img_optimize.sh logo.png banner.jpg downloads/
```

## Example Output

```
% ./img_optimize.sh --quality 85 sample-images/
Optimizing images with quality: 85

Processing directory: sample-images/
✓ sample-images/beach-sunset.jpg
  2MB → 456KB (saved 1MB, 76%)
✓ sample-images/cat-portrait.png
  3MB → 892KB (saved 2MB, 70%)
✓ sample-images/food-photo.webp
  1MB → 312KB (saved 780KB, 74%)

Summary:
Processed: 3 images
Total size: 6MB → 1MB
Total saved: 4MB (73%)
```

## How It Works

The script uses ImageMagick to optimize images with lossy compression:

- Strips metadata (EXIF data, thumbnails, etc.) to reduce file size
- Applies quality compression (default: 85%)
- Creates new files with `.optimized` suffix (originals are preserved)
- Supports JPEG, PNG, WebP, and GIF formats

## Installation

Requires ImageMagick:

```bash
# macOS
brew install imagemagick

# Linux (Debian/Ubuntu)
sudo apt-get install imagemagick

# Linux (Fedora/RHEL)
sudo dnf install ImageMagick
```
