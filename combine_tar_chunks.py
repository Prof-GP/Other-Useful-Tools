#!/usr/bin/env python3
"""
Combine chunked tar.gz files into a single file.

Supports common naming patterns:
  - file.tar.gz.001, file.tar.gz.002, ...
  - file.tar.gz.aa, file.tar.gz.ab, ...
  - file.tar.gz.part1, file.tar.gz.part2, ...

Usage:
  python combine_chunks.py <chunk_file_or_pattern> [-o OUTPUT]

Examples:
  python combine_chunks.py backup.tar.gz.001
  python combine_chunks.py backup.tar.gz.aa -o restored_backup.tar.gz
  python combine_chunks.py "C:\chunks\archive.tar.gz.part1"
"""

import argparse
import glob
import hashlib
import os
import re
import sys
from pathlib import Path


def find_chunks(input_path: str) -> list[Path]:
    """Discover and return all chunk files in sorted order."""
    path = Path(input_path).resolve()
    parent = path.parent
    name = path.name

    # Strip the chunk suffix to get the base name
    # Matches: .001, .aa, .part1, .chunk1, etc.
    patterns = [
        (r"^(.+)\.\d+$", r"\1"),          # .001, .002
        (r"^(.+)\.[a-z]+$", r"\1"),        # .aa, .ab (split output)
        (r"^(.+)\.part\d+$", r"\1"),       # .part1, .part2
        (r"^(.+)\.chunk\d+$", r"\1"),      # .chunk1, .chunk2
    ]

    base_name = None
    for pattern, replacement in patterns:
        match = re.match(pattern, name)
        if match:
            base_name = re.sub(pattern, replacement, name)
            break

    if not base_name:
        print(f"Error: Could not determine base name from '{name}'.")
        print("Expected patterns: .001, .aa, .part1, .chunk1")
        sys.exit(1)

    # Glob for all chunks matching the base name
    candidates = sorted(parent.glob(f"{glob.escape(base_name)}.*"))

    # Filter to only valid chunk suffixes
    chunk_pattern = re.compile(
        re.escape(base_name) + r"\.(\d+|[a-z]+|part\d+|chunk\d+)$"
    )
    chunks = [f for f in candidates if chunk_pattern.match(f.name)]

    if not chunks:
        print(f"Error: No chunk files found matching base name '{base_name}' in {parent}")
        sys.exit(1)

    # Sort chunks naturally (numeric-aware)
    def sort_key(p: Path) -> tuple:
        suffix = p.name[len(base_name) + 1:]  # everything after "base."
        # Try numeric sort first
        num_match = re.match(r"(?:part|chunk)?(\d+)$", suffix)
        if num_match:
            return (0, int(num_match.group(1)))
        # Alphabetic sort for split-style (aa, ab, ...)
        return (1, suffix)

    chunks.sort(key=sort_key)
    return chunks


def derive_output_name(chunks: list[Path]) -> Path:
    """Derive the output filename by stripping the chunk suffix."""
    name = chunks[0].name
    for pattern in [r"\.\d+$", r"\.[a-z]+$", r"\.part\d+$", r"\.chunk\d+$"]:
        stripped = re.sub(pattern, "", name)
        if stripped != name:
            return chunks[0].parent / stripped
    return chunks[0].parent / (name + ".combined")


def combine(chunks: list[Path], output: Path, buffer_size: int = 8 * 1024 * 1024) -> None:
    """Combine chunk files into a single output file."""
    if output.exists():
        resp = input(f"Output file '{output}' already exists. Overwrite? [y/N]: ")
        if resp.lower() != "y":
            print("Aborted.")
            sys.exit(0)

    total_size = sum(c.stat().st_size for c in chunks)
    written = 0

    print(f"Combining {len(chunks)} chunks into: {output}")
    print(f"Total size: {total_size / (1024**2):.2f} MB")
    print()

    md5 = hashlib.md5()
    sha256 = hashlib.sha256()

    with open(output, "wb") as out_f:
        for i, chunk in enumerate(chunks, 1):
            chunk_size = chunk.stat().st_size
            chunk_written = 0
            print(f"  [{i}/{len(chunks)}] {chunk.name} ({chunk_size / (1024**2):.2f} MB)")

            with open(chunk, "rb") as in_f:
                while True:
                    data = in_f.read(buffer_size)
                    if not data:
                        break
                    out_f.write(data)
                    md5.update(data)
                    sha256.update(data)
                    chunk_written += len(data)
                    written += len(data)

                    pct = (written / total_size) * 100 if total_size else 100
                    print(f"\r    Progress: {pct:6.2f}%", end="", flush=True)

            print()

    print()
    print(f"Done! Output: {output}")
    print(f"  Size:   {output.stat().st_size:,} bytes")
    print(f"  MD5:    {md5.hexdigest()}")
    print(f"  SHA256: {sha256.hexdigest()}")


def main():
    parser = argparse.ArgumentParser(
        description="Combine chunked tar.gz files into a single file."
    )
    parser.add_argument(
        "input",
        help="Path to any one of the chunk files (e.g., backup.tar.gz.001)",
    )
    parser.add_argument(
        "-o", "--output",
        help="Output file path (default: auto-detected by stripping chunk suffix)",
    )
    parser.add_argument(
        "-b", "--buffer-size",
        type=int,
        default=8,
        help="Read buffer size in MB (default: 8)",
    )
    args = parser.parse_args()

    chunks = find_chunks(args.input)

    if args.output:
        output = Path(args.output).resolve()
    else:
        output = derive_output_name(chunks)

    print(f"Found {len(chunks)} chunk(s):")
    for c in chunks:
        print(f"  {c.name}")
    print()

    combine(chunks, output, buffer_size=args.buffer_size * 1024 * 1024)


if __name__ == "__main__":
    main()
