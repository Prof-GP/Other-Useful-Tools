<#
.SYNOPSIS
    Combine chunked tar.gz files into a single file.

.DESCRIPTION
    Supports common naming patterns:
      - file.tar.gz.001, file.tar.gz.002, ...
      - file.tar.gz.aa, file.tar.gz.ab, ...
      - file.tar.gz.part1, file.tar.gz.part2, ...

.PARAMETER InputFile
    Path to any one of the chunk files (e.g., backup.tar.gz.001).

.PARAMETER OutputFile
    Optional output file path. If omitted, auto-detected by stripping the chunk suffix.

.PARAMETER BufferSizeMB
    Read buffer size in MB (default: 8).

.EXAMPLE
    .\Combine-Chunks.ps1 -InputFile "backup.tar.gz.001"

.EXAMPLE
    .\Combine-Chunks.ps1 -InputFile "backup.tar.gz.aa" -OutputFile "restored.tar.gz"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile,

    [Parameter(Mandatory = $false)]
    [int]$BufferSizeMB = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-Chunks {
    param([string]$Path)

    $resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop
    $parent = Split-Path -Parent $resolvedPath
    $name = Split-Path -Leaf $resolvedPath

    # Determine base name by stripping chunk suffix
    $suffixPatterns = @(
        @{ Pattern = '^(.+)\.\d+$';       Replace = '$1' }   # .001, .002
        @{ Pattern = '^(.+)\.[a-z]+$';    Replace = '$1' }   # .aa, .ab
        @{ Pattern = '^(.+)\.part\d+$';   Replace = '$1' }   # .part1, .part2
        @{ Pattern = '^(.+)\.chunk\d+$';  Replace = '$1' }   # .chunk1, .chunk2
    )

    $baseName = $null
    foreach ($sp in $suffixPatterns) {
        if ($name -match $sp.Pattern) {
            $baseName = $name -replace $sp.Pattern, $sp.Replace
            break
        }
    }

    if (-not $baseName) {
        throw "Could not determine base name from '$name'. Expected patterns: .001, .aa, .part1, .chunk1"
    }

    # Find all matching chunk files
    $candidates = Get-ChildItem -Path $parent -Filter "$baseName.*" -File | Where-Object {
        $_.Name -match "^$([regex]::Escape($baseName))\.(\d+|[a-z]+|part\d+|chunk\d+)$"
    }

    if (-not $candidates -or $candidates.Count -eq 0) {
        throw "No chunk files found matching base name '$baseName' in $parent"
    }

    # Sort chunks naturally
    $sorted = $candidates | Sort-Object {
        $suffix = $_.Name.Substring($baseName.Length + 1)
        # Try numeric patterns
        if ($suffix -match '^(?:part|chunk)?(\d+)$') {
            return [int64]$Matches[1]
        }
        # Alphabetic fallback — convert to ordinal for proper sort
        $ordinal = 0
        foreach ($ch in $suffix.ToCharArray()) {
            $ordinal = $ordinal * 26 + ([int][char]$ch - [int][char]'a' + 1)
        }
        return $ordinal + 1000000  # offset so alpha sorts after numeric
    }

    return @{
        BaseName = $baseName
        Parent   = $parent
        Chunks   = @($sorted)
    }
}

function Get-OutputName {
    param($ChunkInfo)

    $name = $ChunkInfo.Chunks[0].Name
    $patterns = @('\.\d+$', '\.[a-z]+$', '\.part\d+$', '\.chunk\d+$')

    foreach ($p in $patterns) {
        $stripped = $name -replace $p, ''
        if ($stripped -ne $name) {
            return Join-Path $ChunkInfo.Parent $stripped
        }
    }
    return Join-Path $ChunkInfo.Parent "$name.combined"
}

# ---- Main ----

try {
    $chunkInfo = Find-Chunks -Path $InputFile
    $chunks = $chunkInfo.Chunks

    Write-Host "Found $($chunks.Count) chunk(s):" -ForegroundColor Cyan
    foreach ($c in $chunks) {
        Write-Host "  $($c.Name)"
    }
    Write-Host ""

    # Determine output path
    if ($OutputFile) {
        $outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
    }
    else {
        $outPath = Get-OutputName -ChunkInfo $chunkInfo
    }

    # Check for existing output
    if (Test-Path $outPath) {
        $response = Read-Host "Output file '$outPath' already exists. Overwrite? [y/N]"
        if ($response -ne 'y') {
            Write-Host "Aborted." -ForegroundColor Yellow
            exit 0
        }
    }

    $totalSize = ($chunks | Measure-Object -Property Length -Sum).Sum
    $totalSizeMB = [math]::Round($totalSize / 1MB, 2)

    Write-Host "Combining $($chunks.Count) chunks into: $outPath" -ForegroundColor Green
    Write-Host "Total size: $totalSizeMB MB"
    Write-Host ""

    $bufferSize = $BufferSizeMB * 1MB
    $buffer = New-Object byte[] $bufferSize
    $written = 0

    # Hash computation
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    $outStream = [System.IO.File]::Create($outPath)

    try {
        for ($i = 0; $i -lt $chunks.Count; $i++) {
            $chunk = $chunks[$i]
            $chunkSizeMB = [math]::Round($chunk.Length / 1MB, 2)
            Write-Host "  [$($i + 1)/$($chunks.Count)] $($chunk.Name) ($chunkSizeMB MB)"

            $inStream = [System.IO.File]::OpenRead($chunk.FullName)
            try {
                while (($bytesRead = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $outStream.Write($buffer, 0, $bytesRead)
                    $md5.TransformBlock($buffer, 0, $bytesRead, $null, 0) | Out-Null
                    $sha256.TransformBlock($buffer, 0, $bytesRead, $null, 0) | Out-Null
                    $written += $bytesRead

                    if ($totalSize -gt 0) {
                        $pct = [math]::Round(($written / $totalSize) * 100, 2)
                        Write-Host "`r    Progress: $($pct.ToString('F2'))%" -NoNewline
                    }
                }
            }
            finally {
                $inStream.Close()
            }
            Write-Host ""
        }
    }
    finally {
        $outStream.Close()
    }

    # Finalize hashes
    $md5.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null
    $sha256.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null

    $md5Hash = [BitConverter]::ToString($md5.Hash).Replace("-", "").ToLower()
    $sha256Hash = [BitConverter]::ToString($sha256.Hash).Replace("-", "").ToLower()

    $finalSize = (Get-Item $outPath).Length

    Write-Host ""
    Write-Host "Done! Output: $outPath" -ForegroundColor Green
    Write-Host "  Size:   $($finalSize.ToString('N0')) bytes"
    Write-Host "  MD5:    $md5Hash"
    Write-Host "  SHA256: $sha256Hash"
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
finally {
    if ($md5) { $md5.Dispose() }
    if ($sha256) { $sha256.Dispose() }
}
