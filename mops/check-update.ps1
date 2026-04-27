[CmdletBinding()]
param (
    [Parameter()]
    [String]
    $SiteUrl = "http://momoirocode.web.fc2.com/mocode.html"
    ,$ReadFile = "update-hash.dat"
)


$content = [String](Invoke-WebRequest $SiteUrl -UseBasicParsing).Content

$stream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($content))

$hash = Get-FileHash -InputStream $stream -Algorithm SHA256

$oldHash = if (Test-Path $ReadFile) { (Get-Content $ReadFile -Raw) } else { "no data" }

Write-Debug $hash.Hash
Write-Debug $oldHash

if ($oldHash -eq $hash.Hash){
    Write-Debug "hash has not updated."
    return $false
}else {
    Write-Debug "hash has update."
    return $hash
}

