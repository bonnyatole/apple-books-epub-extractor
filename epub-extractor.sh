#!/usr/bin/env bash

set -u

# ============================================================
# EPUB Extractor
#
# Extracts EPUB books from an iOS/iPadOS backup containing
# an Apple Books library.
#
# Usage:
#   ./epub-extractor.sh "<backup-path>" "<output-path>"
#
# Example:
#   ./epub-extractor.sh \
#       "/path/to/ios-backup" \
#       "/path/to/recovered-epubs"
# ============================================================


# ============================================================
# Configuration
# ============================================================

BOOKS_ROOT="Library/Mobile Documents/iCloud~com~apple~iBooks/Documents"


# ============================================================
# Global counters
# ============================================================

TOTAL_BOOKS=0
RECOVERED_BOOKS=0
SKIPPED_BOOKS=0
FAILED_BOOKS=0


# ============================================================
# Print usage information
# ============================================================

print_usage() {
    echo
    echo "Usage:"
    echo "  $0 <backup-path> <output-path>"
    echo
    echo "Arguments:"
    echo "  backup-path   Path to the iOS/iPadOS backup"
    echo "  output-path   Directory where recovered EPUBs will be saved"
    echo
    echo "Example:"
    echo "  $0 \"/path/to/ios-backup\" \"/path/to/recovered-epubs\""
    echo
}


# ============================================================
# Validate command-line arguments
# ============================================================

validate_arguments() {

    if [[ $# -ne 2 ]]; then
        print_usage
        exit 1
    fi

    BACKUP_DIR="$1"
    OUTPUT_DIR="$2"

    # Resolve backup path to an absolute path
    BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd -P)" || {
        echo "ERROR: Backup directory does not exist."
        exit 1
    }

    # Resolve relative output paths against the original working directory
    if [[ "$OUTPUT_DIR" != /* ]]; then
        OUTPUT_DIR="$(pwd -P)/$OUTPUT_DIR"
    fi
}


# ============================================================
# Validate backup and required dependencies
# ============================================================

validate_environment() {

    MANIFEST_DB="$BACKUP_DIR/Manifest.db"

    if [[ ! -f "$MANIFEST_DB" ]]; then
        echo "ERROR: Manifest.db not found in:"
        echo "  $BACKUP_DIR"
        exit 1
    fi

    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "ERROR: sqlite3 is required but was not found."
        exit 1
    fi

    if ! command -v zip >/dev/null 2>&1; then
        echo "ERROR: zip is required but was not found."
        exit 1
    fi

    if ! command -v unzip >/dev/null 2>&1; then
        echo "ERROR: unzip is required but was not found."
        exit 1
    fi
}


# ============================================================
# Prepare output directory
# ============================================================

prepare_output_directory() {

    if ! mkdir -p "$OUTPUT_DIR"; then
        echo "ERROR: Cannot create output directory:"
        echo "  $OUTPUT_DIR"
        exit 1
    fi

    if [[ ! -w "$OUTPUT_DIR" ]]; then
        echo "ERROR: Output directory is not writable:"
        echo "  $OUTPUT_DIR"
        exit 1
    fi
}


# ============================================================
# Find EPUB packages in Manifest.db
# ============================================================

find_epubs() {

    BOOK_LIST="$WORK_DIR/books.tsv"

    if ! sqlite3 \
        -noheader \
        -separator $'\t' \
        "$MANIFEST_DB" "
            SELECT fileID, relativePath
            FROM Files
            WHERE flags = 2
              AND relativePath LIKE '$BOOKS_ROOT/%.epub';
        " > "$BOOK_LIST"; then

        echo "ERROR: Failed to query Manifest.db."
        exit 1
    fi

    TOTAL_BOOKS=$(wc -l < "$BOOK_LIST" | tr -d ' ')

    echo "EPUB packages found: $TOTAL_BOOKS"
    echo
}


# ============================================================
# Escape a string for use inside a SQLite single-quoted value
# ============================================================

escape_sql_string() {

    local value="$1"

    # Replace every single quote with two single quotes.
    printf '%s' "${value//\'/\'\'}"
}


# ============================================================
# Recover a single EPUB
# ============================================================

recover_epub() {

    local root_file_id="$1"
    local relative_path="$2"
    local index="$3"

    local book_name
    local destination
    local book_work
    local file_list

    local expected_files
    local copied_files=0
    local missing_files=0

    book_name="${relative_path##*/}"
    destination="${OUTPUT_DIR%/}/$book_name"

    echo "----------------------------------------------"
    echo "[$index/$TOTAL_BOOKS] $book_name"
    echo "----------------------------------------------"

    # Do not overwrite an existing recovered EPUB.
    if [[ -f "$destination" ]]; then
        echo "  Already exists. Skipping."
        SKIPPED_BOOKS=$((SKIPPED_BOOKS + 1))
        echo
        return
    fi

    book_work="$WORK_DIR/book-$index"
    file_list="$book_work/files.tsv"

    rm -rf "$book_work"

    if ! mkdir -p "$book_work"; then
        echo "  ERROR: Unable to create temporary directory."
        FAILED_BOOKS=$((FAILED_BOOKS + 1))
        echo
        return
    fi

    # Escape the EPUB path before inserting it into SQL.
    local escaped_path
    escaped_path="$(escape_sql_string "$relative_path")"

    # Find all files belonging to this EPUB package.
	if ! sqlite3 \
		-noheader \
		-separator $'\t' \
		"$MANIFEST_DB" "
			SELECT fileID, relativePath
			FROM Files
			WHERE flags = 1
			AND relativePath LIKE '$escaped_path/%'
			ORDER BY relativePath;
		" > "$file_list"; then
	
		echo "  ERROR: Failed to query Manifest.db."
		rm -rf "$book_work"
		FAILED_BOOKS=$((FAILED_BOOKS + 1))
		echo
		return
	fi

    expected_files=$(wc -l < "$file_list" | tr -d ' ')

    if [[ "$expected_files" -eq 0 ]]; then
        echo "  ERROR: No files found inside the EPUB package."
        echo "  The package exists in Manifest.db, but its contents"
        echo "  are not present in this backup."
        FAILED_BOOKS=$((FAILED_BOOKS + 1))
        rm -rf "$book_work"
        echo
        return
    fi

    # --------------------------------------------------------
    # Copy every EPUB component from the backup.
    # --------------------------------------------------------

    while IFS=$'\t' read -r file_id file_relative_path; do

        [[ -z "$file_id" ]] && continue
        [[ -z "$file_relative_path" ]] && continue

        local source_file
        local epub_relative_path
        local destination_file

        # iOS backup files are stored as:
        #
        #   <first-two-characters-of-fileID>/<fileID>
        #
        source_file="$BACKUP_DIR/${file_id:0:2}/$file_id"

        epub_relative_path="${file_relative_path#"$relative_path/"}"

        destination_file="$book_work/$epub_relative_path"

        if [[ ! -f "$source_file" ]]; then
            echo "  MISSING: $epub_relative_path"
            missing_files=$((missing_files + 1))
            continue
        fi

        if ! mkdir -p "$(dirname "$destination_file")"; then
            echo "  ERROR: Unable to create directory for:"
            echo "    $epub_relative_path"
            missing_files=$((missing_files + 1))
            continue
        fi

        if ! cp "$source_file" "$destination_file"; then
            echo "  ERROR: Unable to copy:"
            echo "    $epub_relative_path"
            missing_files=$((missing_files + 1))
            continue
        fi

        copied_files=$((copied_files + 1))

    done < "$file_list"


    # --------------------------------------------------------
    # Make sure every file was recovered.
    # --------------------------------------------------------

    if [[ "$missing_files" -gt 0 ]]; then

        echo
        echo "  INCOMPLETE EPUB"
        echo "  Expected files : $expected_files"
        echo "  Recovered files: $copied_files"
        echo "  Missing files  : $missing_files"
        echo "  EPUB will not be created."

        FAILED_BOOKS=$((FAILED_BOOKS + 1))

        rm -rf "$book_work"

        echo
        return
    fi


    # --------------------------------------------------------
    # Verify that mimetype exists.
    # --------------------------------------------------------

    if [[ ! -f "$book_work/mimetype" ]]; then

        echo "  ERROR: EPUB mimetype file is missing."
        echo "  EPUB will not be created."

        FAILED_BOOKS=$((FAILED_BOOKS + 1))

        rm -rf "$book_work"

        echo
        return
    fi
    
    if [[ "$(cat "$book_work/mimetype")" != "application/epub+zip" ]]; then

		echo "  ERROR: Invalid EPUB mimetype."
		echo "  EPUB will not be created."
	
		FAILED_BOOKS=$((FAILED_BOOKS + 1))
	
		rm -rf "$book_work"
	
		echo
		return
	fi


    # --------------------------------------------------------
    # Create the EPUB archive.
    #
    # EPUB requires:
    #
    #   1. mimetype must be the first entry
    #   2. mimetype must not be compressed
    # --------------------------------------------------------

    if ! (
        cd "$book_work" || exit 1

        zip -q -X0 "$destination" mimetype || exit 1

        zip -q -Xr9D "$destination" . -x mimetype || exit 1
    ); then

        echo "  ERROR: Failed to create EPUB archive."

        rm -f "$destination"
        rm -rf "$book_work"

        FAILED_BOOKS=$((FAILED_BOOKS + 1))

        echo
        return
    fi


    # --------------------------------------------------------
    # Validate the resulting EPUB.
    # --------------------------------------------------------

    if ! unzip -tq "$destination" >/dev/null 2>&1; then

        echo "  ERROR: Created EPUB failed archive validation."

        rm -f "$destination"
        rm -rf "$book_work"

        FAILED_BOOKS=$((FAILED_BOOKS + 1))

        echo
        return
    fi


    # --------------------------------------------------------
    # Success.
    # --------------------------------------------------------

    local size
    size="$(du -h "$destination" | cut -f1)"

    echo "  OK"
    echo "  Output: $destination"
    echo "  Size:   $size"

    RECOVERED_BOOKS=$((RECOVERED_BOOKS + 1))

    rm -rf "$book_work"

    echo
}


# ============================================================
# Print final summary
# ============================================================

print_summary() {

    echo
    echo "=============================================="
    echo " Extraction completed"
    echo "=============================================="
    echo
    echo "EPUBs found       : $TOTAL_BOOKS"
    echo "Recovered         : $RECOVERED_BOOKS"
    echo "Already existing  : $SKIPPED_BOOKS"
    echo "Failed/incomplete : $FAILED_BOOKS"
    echo
    echo "Output directory:"
    echo "  $OUTPUT_DIR"
    echo

    if [[ "$FAILED_BOOKS" -gt 0 ]]; then
        echo "WARNING: Some EPUBs could not be recovered."
        echo "The original backup was not modified."
        echo
    fi
}


# ============================================================
# Main
# ============================================================

main() {

    validate_arguments "$@"

    validate_environment

    prepare_output_directory

    # Create a temporary working directory.
    if ! WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/epub-extractor.XXXXXX")"; then
		echo "ERROR: Unable to create temporary working directory."
		exit 1
	fi

    # Always remove temporary files when the script exits.
    trap 'rm -rf "$WORK_DIR"' EXIT

    echo
    echo "=============================================="
    echo " EPUB Extractor"
    echo "=============================================="
    echo
    echo "Backup:"
    echo "  $BACKUP_DIR"
    echo
    echo "Output:"
    echo "  $OUTPUT_DIR"
    echo

    find_epubs

    if [[ "$TOTAL_BOOKS" -eq 0 ]]; then
        echo "No EPUB packages were found in the Apple Books"
        echo "section of this backup."
        echo
        exit 0
    fi

    local index=0

    while IFS=$'\t' read -r root_file_id relative_path; do

        [[ -z "$relative_path" ]] && continue

        index=$((index + 1))

        recover_epub \
            "$root_file_id" \
            "$relative_path" \
            "$index"

    done < "$BOOK_LIST"

    print_summary
}


main "$@"
