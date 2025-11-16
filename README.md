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

