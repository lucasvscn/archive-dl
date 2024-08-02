#!/usr/bin/env bash
# vim: set et ts=2 sw=2 :
#
# archive-dl.sh - Download files from archive.org
#
# Url....: https://github.com/lucasvscn/archive-dl
# Author.: Lucas Vasconcelos <lucas@vasconcelos.cc>
# License: MIT
#
# ----------------------------------------------------------------------------
#
# This script downloads files from archive.org with a given identifier.
# 
# It crawls the archive.org website to find the files and their URLs.
#
# Usage:
#  archive-dl.sh [options] <identifier> [destination]
#
# Arguments:
#  identifier      Identifier of the archive.org item
#  destination     Destination directory (default: current directory)
#
# Options:
#  -h, --help      Show this help message and exit
#  -v, --version   Show version information and exit
#  -q, --quiet     Do not output any message
#  -f, --force     Overwrite existing files
#  -j, --jobs      Number of parallel downloads (default: 4)
#  --list          List available files with URLs and sizes
#  --list-urls     List available URLs only (useful for piping)
#
# Example:
#  archive-dl.sh "archiveteam-warrior-20210509" "/tmp"
#
# ----------------------------------------------------------------------------
#

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

VERSION="1.0.0"

# Default options
QUIET=false
FORCE=false
JOBS=4
LIST=false
LIST_TYPE="all" # all, urls
IDENTIFIER=""
DESTINATION="."

# ----------------------------------------------------------------------------
# Functions
# ----------------------------------------------------------------------------

###
# Print a message
# Usage: log <message>
# Example: log "Hello, world!"
# Globals: QUIET
#
log() {
  if [ "$QUIET" = false ]; then
    echo "$1"
  fi
}

###
# Print an error message
# Usage: error <message>
# Example: error "Something went wrong!"
# Exit code: 1
# Globals: none
#
error() {
  echo "Error: $1" >&2
  exit 1
}

###
# Print the help message
# Usage: help
# Globals: none
#
help() {
  echo "Usage: archive-dl.sh [options] <identifier> [destination]"
  echo
  echo "Arguments:"
  echo "  identifier      Identifier of the archive.org item"
  echo "  destination     Destination directory (default: current directory)"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -v, --version   Show version information and exit"
  echo "  -q, --quiet     Do not output any message"
  echo "  -f, --force     Overwrite existing files"
  echo "  -j, --jobs      Number of parallel downloads (default: 4)"
  echo "  --list          List available files with URLs and sizes"
  echo "  --list-urls     List available URLs only (useful for piping)"
  echo
  echo "Example:"
  echo "  archive-dl.sh \"archiveteam-warrior-20210509\" \"/tmp\""
  exit 0
}

###
# Print the version information
# Usage: version
# Globals: VERSION
#
version() {
  echo "archive-dl.sh $VERSION"
  exit 0
}

###
# URL enconde a string
# Usage: urlencode <string>
# Example: urlencode "Hello, world!"
# Dependencies: jq
#
urlencode() {
  local string="$1"
  echo "$string" | jq -R -r @uri
}

###
# URL decode a string
# Usage: urldecode <string>
# Example: urldecode "Hello%2C%20world%21"
#
urldecode() {
  local encoded="${*//+/ }"
  printf '%b' "${encoded//%/\\x}"
}

###
# Build the download URL
# Usage: build_url <identifier> <file>
# Example: build_url "archiveteam-warrior-20210509" "archiveteam-warrior-20210509.warc.gz"
# Globals: none
# Dependencies: none
# Exit code: 0
# Returns: URL
#
build_url() {
  local identifier="$1"
  local file=$(urlencode "$2")
  echo "https://archive.org/download/$identifier/$file"
}

###
# List available files with URLs and sizes
# Usage: list
# Globals: IDENTIFIER
# Dependencies: curl, jq
#
list() {
  local url="https://archive.org/metadata/$IDENTIFIER"
  local json=$(curl -s "$url" | jq -r '.files[] | "\(.name) \(.size)"')
  echo "$json"
}

###
# List available URLs only
# Usage: list_urls
# Globals: IDENTIFIER
# Dependencies: curl, jq, build_url
#
list_urls() {
  # If "source.txt" exists, read the URLs from it
  if [ -f "$DESTINATION/source.txt" ]; then
    cat "$DESTINATION/source.txt"
    return
  fi

  local url="https://archive.org/metadata/$IDENTIFIER"
  local list=$(curl -s "$url" | jq -r '.files[] | .name' | while read -r file; do build_url "$IDENTIFIER" "$file"; done)

  # Save the list to a file "source.txt" inside the destination directory
  echo "$list" > "$DESTINATION/source.txt"

  echo "$list"
}

###
# Prepare URLs for download
# Usage: prepare_urls <urls>
# Globals: DESTINATION
# Example: prepare_urls "https://example.com/file1 https://example.com/file2"
# Output: url1 -o file1 url2 -o file2
#
prepare_urls() {
  local urls="$1"
  local list=$(echo "$urls" | while read -r url; do echo "$url -o \"$DESTINATION/$(urldecode $(basename "$url"))\""; done)
  echo "$list"
}

###
# Download files
# Usage: download_files <urls> <destination>
# Globals: FORCE, JOBS, QUIET
# Dependencies: prepare_urls 
#
download_files() {
  local urls="$1"
  local destination="$2"
  local list=$(prepare_urls "$urls")
  local cmd="curl -L --parallel-max $JOBS --parallel-immediate -Z"

  if [ "$QUIET" = true ]; then
    cmd="$cmd -s"
  else
    cmd="$cmd --progress-bar"
  fi

  if [ "$FORCE" = false ]; then
    cmd="$cmd -C -"
  fi

  cmd="$cmd $(echo "$list" | sed 's/$/ \\/g')"
  cmd="${cmd%\\}"

  echo "$cmd" > "$destination/download.sh"
  eval "$cmd"
}

# ----------------------------------------------------------------------------
# Parse arguments
# ----------------------------------------------------------------------------
# Dependencies: getopt
#
ARGS=$(getopt -o hvqfj: --long help,version,quiet,force,jobs:,list,list-urls -n "archive-dl.sh" -- "$@")
eval set -- "$ARGS"

while true; do
  case "$1" in
   -h | --help)
      help
      ;;
    -v | --version)
      version
      ;;
    -q | --quiet)
      QUIET=true
      shift
      ;;
    -f | --force)
      FORCE=true
      shift
      ;;
    -j | --jobs)
      JOBS="$2"
      shift 2
      ;;
    --list)
      LIST=true
      shift
      ;;
    --list-urls)
      LIST=true
      LIST_TYPE="urls"
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      error "Invalid option: $1"
      ;;
  esac
done

# Check if the identifier was provided
# Dependencies: shift
# Globals: IDENTIFIER
# Exit code: 1
#
if [ -z "$1" ]; then
  error "Identifier not provided"
fi

IDENTIFIER="$1"
shift

# Check if the destination was provided
# Dependencies: shift
# Globals: DESTINATION
# Exit code: 1
#
if [ -n "$1" ]; then
  DESTINATION="$1"
fi

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

# List available files with URLs and sizes
# Dependencies: list
# Exit code: 0
# Globals: LIST, LIST_TYPE
#
if [ "$LIST" = true ]; then
  case "$LIST_TYPE" in
    all)
      list
      ;;
    urls)
      list_urls
      ;;
  esac
  exit 0
fi

# Check if the destination directory exists
# Dependencies: DESTINATION
#
if [ ! -d "$DESTINATION" ]; then
  error "Destination directory does not exist: $DESTINATION"
fi

# Download the files
# Dependencies: DESTINATION, IDENTIFIER, FORCE, JOBS
# Globals: QUIET
#
log "Downloading files from archive.org..."

urls=$(list_urls)
download_files "$urls" "$DESTINATION"

