🔒 Malware Sample Packager
Safely package suspicious files for security analysis with password protection.

What it does

Zips suspicious files with the industry-standard password infected and renames them with _suspicious suffix. Prevents accidental execution and bypasses email filters during incident response.

Usage

```bash
python malware_zipper.py suspicious_file.exe

# Multiple files
python malware_zipper.py file1.exe file2.dll file3.js
```
Output: filename_suspicious.zip (or .b64 for weak encryption)
Password: infected
Features

Auto-downloads 7-Zip if needed (Windows)
Works across Windows, Linux, macOS
Tries multiple compression methods automatically
Cleans up temporary files
No installation required - just Python 3.6+

Perfect for security teams, IT professionals, and incident responders who need to safely transfer malware samples for analysis.

  -------------------------------------------------------------------------------------------------------------------------------------------------------------
  Combine Tar Chunks

  Scripts to reassemble chunked tar.gz files (e.g., from split) back into a single file.
  ┌────────────────────    ┬────────────    ┐
  │       Script           │  Language      │
  ├───────────────────-----┼───────────    ─┤
  │ combine_tar_chunks.py  │   Python       │
  ├────────────────────┼────────────        ┤
  │ Combine_tar_Chunks.ps1 │ PowerShell     │
  └────────────────────    ┴────────────    ┘
  Features:
  - Auto-detects chunk naming patterns (.001, .aa, .part1, .chunk1)
  - Auto-derives output filename from chunk name
  - Buffered I/O (8 MB default) for large files
  - Outputs MD5 and SHA256 hashes of the combined file
  - Progress reporting

  Usage:
  python combine_chunks.py backup.tar.gz.001
  .\Combine-Chunks.ps1 -InputFile "backup.tar.gz.001"
