param([string]$Server = "localhost")
$out = Join-Path $PSScriptRoot "mdx_results.txt"
Remove-Item $out -ErrorAction SilentlyContinue
Get-ChildItem (Join-Path $PSScriptRoot "mdx") -Filter *.mdx | Sort-Object Name | ForEach-Object {
    "===== $($_.Name)" | Out-File $out -Append -Encoding utf8
    & (Join-Path $PSScriptRoot "run_mdx.ps1") -File $_.FullName -Server $Server -MaxRows 15 2>&1 | Out-File $out -Append -Encoding utf8
    "" | Out-File $out -Append -Encoding utf8
}
Write-Host "Saved: $out"
