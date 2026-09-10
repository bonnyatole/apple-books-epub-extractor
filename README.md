# Apple Books EPUB Extractor

A Bash script for recovering user-imported EPUB files from local iOS and iPadOS backups containing Apple Books data.

## Why does this tool exist?

When an EPUB file is imported into Apple Books on an iPhone or iPad, Apple Books stores the book inside its application data rather than in a location that is normally accessible through the Files app or a standard file browser.

This makes it difficult to retrieve the original EPUB file from the device, even though the book can still be read normally in Apple Books.

This tool provides a way to recover those EPUB files from a local iOS/iPadOS backup, when the required book data is physically present in the backup.

## What can be recovered?

This tool is primarily intended for **EPUB files imported into Apple Books by the user**.

For example, you may have an EPUB file obtained from another source and share it to Apple Books from an iPhone or iPad. Apple Books can then be used as an EPUB reader, while the book is stored inside the application's data.

This is the type of EPUB this tool is designed to recover.

Books that were purchased or downloaded directly from the Apple Books Store may use different storage and protection mechanisms. They may therefore **not be recoverable as regular EPUB files using this tool**.

Even for imported EPUBs, recovery is only possible when the required files are physically present in the backup.

## iCloud-synchronized Apple Books libraries

If Apple Books is synchronized through iCloud, a local backup may contain references to books that are part of the user's Apple Books library but whose actual EPUB files are not stored on that particular device.

The extractor will detect these books in Manifest.db, but it can only recover books whose underlying files are physically present in the backup.

Therefore, if a book was imported into Apple Books on an iPad and synchronized to an iPhone through iCloud, the book may appear in the iPhone's Apple Books library and be detected by this tool, while still being impossible to recover from the iPhone backup unless the book was actually downloaded to the iPhone.

## Features

* Recover user-imported EPUB files from iOS and iPadOS backups
* Use Apple Books data stored in `Manifest.db`
* Reconstruct EPUB archives from their individual backup files
* Preserve the original backup
* Do not overwrite existing EPUB files
* Detect incomplete EPUB packages
* Validate the resulting EPUB archives
* Handle spaces and special characters in file and directory names

## Requirements

The script requires:

* Bash
* SQLite 3 (`sqlite3`)
* `zip`
* `unzip`

## Installing the dependencies

### Debian / Ubuntu

```bash
sudo apt install sqlite3 zip unzip
```

### Fedora

```bash
sudo dnf install sqlite zip unzip
```

### Arch Linux

```bash
sudo pacman -S sqlite zip unzip
```

### openSUSE

```bash
sudo zypper install sqlite3 zip unzip
```

## Getting an iOS/iPadOS Backup

The script works with a local iOS or iPadOS backup that contains Apple Books data.

The backup directory must contain a file named:

```text
Manifest.db
```

The backup can be created using Apple's official backup tools on Windows or macOS and then made available on a Linux system.

### Linux users

If you only have access to a Linux computer, one possible solution is to create the backup from a Windows virtual machine.

For example, you can:

1. Set up a Windows virtual machine.
2. Connect the iPhone or iPad to the virtual machine.
3. Install **Apple Devices** from the Microsoft Store.
4. Create a local backup of the device.
5. Make the resulting backup directory available to your Linux system.

The exact steps for configuring USB device access and transferring the backup depend on the virtualization software being used.

For best results, use an **unencrypted local backup**.

## Installation

Clone the repository:

```bash
git clone https://github.com/bonnyatole/apple-books-epub-extractor.git
cd apple-books-epub-extractor
```

Make the script executable:

```bash
chmod +x epub-extractor.sh
```

No additional installation is required.

## Usage

The script accepts exactly two arguments:

```bash
./epub-extractor.sh "<backup-path>" "<output-path>"
```

Where:

* `<backup-path>` is the path to the iOS/iPadOS backup
* `<output-path>` is the directory where recovered EPUB files will be saved

The output directory is created automatically if it does not exist.

Relative and absolute paths are supported.

## Example

```bash
./epub-extractor.sh "/path/to/ios-backup" "/path/to/recovered-epubs"
```

For example, if the backup and output directory are located in the current directory:

```bash
./epub-extractor.sh "./ios-backup" "./recovered-epubs"
```

## Output

During extraction, the script reports the status of each EPUB package.

For example:

```text
==============================================
 EPUB Extractor
==============================================

Backup:
  /path/to/ios-backup

Output:
  /path/to/recovered-epubs

EPUB packages found: 55

----------------------------------------------
[1/55] Hunger Games.epub
----------------------------------------------
  OK
  Output: /path/to/recovered-epubs/Hunger Games.epub
  Size:   2.1M
```

At the end, a summary is displayed:

```text
==============================================
 Extraction completed
==============================================

EPUBs found       : 55
Recovered         : 54
Already existing  : 0
Failed/incomplete : 1
```

Existing EPUB files are skipped and are never overwritten.

## How It Works

Apple Books stores imported books inside its application data.

When a local iOS/iPadOS backup is created, the backup contains a SQLite database called `Manifest.db`. This database describes the files included in the backup.

The script:

1. Searches `Manifest.db` for EPUB packages belonging to Apple Books.
2. Finds the individual files belonging to each EPUB package.
3. Locates the corresponding physical files in the backup.
4. Recreates the original EPUB directory structure.
5. Creates a ZIP archive using the EPUB format requirements.
6. Ensures that the `mimetype` file is the first entry and is stored without compression.
7. Validates the resulting archive using `unzip -t`.

The original backup is only read by the script and is not modified.

## Incomplete EPUBs

An EPUB package may appear in `Manifest.db` without all of its physical files being available in the backup.

If one or more files are missing, the EPUB is considered **incomplete** and is **not created**. This prevents the tool from producing corrupted or partially reconstructed EPUB files.

For example:

```text
[47/55] The Maze Runner.epub
----------------------------------------------
  MISSING: OEBPS/Text/cap55.html

  INCOMPLETE EPUB
  Expected files : 76
  Recovered files: 75
  Missing files  : 1
  EPUB will not be created.
```

An EPUB can also have no files available in the backup at all:

```text
[12/55] Moby Dick.epub
----------------------------------------------
  ERROR: No files found inside the EPUB package.
  The package exists in Manifest.db, but its contents
  are not present in this backup.
```

In both cases, the original backup is left untouched and no incomplete EPUB is written to the output directory.

This behavior is particularly important when working with Apple Books libraries synchronized through iCloud, where `Manifest.db` may contain references to books whose actual content is not stored locally on the device at the time of the backup.


## Limitations

### DRM and protected books

This tool does not remove or bypass DRM, encryption, or other access controls.

It only reconstructs EPUB content that is already available as files in the backup.

### Apple Books Store books

Books purchased or downloaded directly from the Apple Books Store may not be stored as standard, user-accessible EPUB files.

Consequently, this tool is primarily intended for EPUB files that were imported into Apple Books by the user.

### Backup contents

The script cannot recover files that are not physically present in the backup.

The presence of a book in Apple Books or in `Manifest.db` does not guarantee that its complete EPUB content is included in the backup.

### Encrypted backups

Encrypted backups may require additional handling and are not the target of this tool.

## Troubleshooting

### `Manifest.db not found`

Make sure the path supplied as the first argument points to the root directory of the backup.

For example:

```bash
./epub-extractor.sh "/path/to/backup" "./recovered-epubs"
```

The following file should exist:

```text
/path/to/backup/Manifest.db
```

### `sqlite3 is required but was not found`

Install SQLite 3 using your operating system's package manager.

For example, on Debian or Ubuntu:

```bash
sudo apt install sqlite3
```

### Some EPUBs are reported as incomplete

This means that one or more files required to reconstruct the EPUB are missing from the backup.

The script intentionally does not create incomplete EPUB archives.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
