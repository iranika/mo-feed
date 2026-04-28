[CmdletBinding()]
param (
    [Parameter()]
    [String]
    $SiteUrl = "http://momoirocode.web.fc2.com/mocode.html"
    ,$OutFile = "4komaData.json"
    ,[switch] $ReturnNewContentOnly
    ,[switch] $FullFetch
    ,[int] $ThrottleLimit = 8
)

Import-Module AngleParse

$dom = Invoke-WebRequest $SiteUrl | Select-HtmlContent "div.menu > ul > li", @{
    title = "a"
    href = "a", ([AngleParse.Attr]::Href)
}

$list = $dom | % {
    #NOTE: 相対参照から絶対参照に変更、
    if (([string]$_.href).Contains("http://momoirocode.web.fc2.com")){
        return $_
    }else{
        $result = $_
        $result.href = $_.href -replace "^/", "http://momoirocode.web.fc2.com/"
        return $result
    }
}

class PageData {
    [string] $Title
    [string] $BaseUrl
    [string[]] $ImagesUrl
    PageData([string]$title, [string]$baseUrl, [string[]]$images){
        $this.Title = $title
        $this.BaseUrl = $baseUrl
        $this.ImagesUrl = $images
    }
}

function Get-ImagesUrlFromPage {
    param(
        [Parameter(Mandatory)]
        [string] $PageUrl
    )
    return Invoke-WebRequest $PageUrl | Select-HtmlContent "img", @{
        src = [AngleParse.Attr]::Src
    } | ? { !([string]$_.src).Contains("counter_img.php?id=50") } | % { $_.src }
}

if ($ReturnNewContentOnly){
    #JSON全体を生成せずに最新話だけ出力するオプション
    $imgs = Get-ImagesUrlFromPage -PageUrl $list[-1].href
    return New-Object PageData($list[-1].Title, $list[-1].href, $imgs)
}

$existingByUrl = @{}
if (!$FullFetch -and (Test-Path $OutFile)) {
    try {
        $existing = Get-Content -Raw $OutFile | ConvertFrom-Json
        foreach ($e in @($existing)) {
            if ($null -ne $e.BaseUrl -and $e.BaseUrl -ne "") {
                $existingByUrl[$e.BaseUrl] = $e
            }
        }
    } catch {
        Write-Warning "Failed to read existing json. fall back to FullFetch. file=$OutFile"
        $FullFetch = $true
    }
}

if ($FullFetch -or $existingByUrl.Count -eq 0) {
    $obj = 0..($list.count -1) | % -parallel -ThrottleLimit $ThrottleLimit {
        #NOTE: parallelオプションを使うとソートが必要になるので注意
        #NOTE: $listのindexを取るためにあえて0..MaxLength-1でForEachしている
        Import-Module AngleParse
        class PageData {
            [string] $Title
            [string] $BaseUrl
            [string[]] $ImagesUrl
            PageData([string]$title, [string]$baseUrl, [string[]]$images){
                $this.Title = $title
                $this.BaseUrl = $baseUrl
                $this.ImagesUrl = $images
            }
        }
        function Get-ImagesUrlFromPage {
            param([Parameter(Mandatory)][string] $PageUrl)
            return Invoke-WebRequest $PageUrl | Select-HtmlContent "img", @{
                src = [AngleParse.Attr]::Src
            } | ? { !([string]$_.src).Contains("counter_img.php?id=50") } | % { $_.src }
        }

        $imgs = Get-ImagesUrlFromPage -PageUrl ($using:list)[$_].href
        $result = New-Object PageData(($using:list)[$_].title, ($using:list)[$_].href, $imgs)
        return @{
            Index = $_
            Page = $result
        }
    } | Sort-Object -Property Index | % { $_.Page }
} else {
    # 差分取得: 直近3話だけ取り直して既存にマージする
    $tailCount = 3
    $startIndex = [Math]::Max(0, $list.Count - $tailCount)
    $targets = $startIndex..($list.Count - 1) | % {
        $i = $_
        [pscustomobject]@{
            Index = $i
            Title = [string]$list[$i].title
            Href  = [string]$list[$i].href
        }
    }

    $fetchedByUrl = @{}
    if ($targets.Count -gt 0) {
        $fetched = $targets | % -parallel -ThrottleLimit $ThrottleLimit {
            Import-Module AngleParse
            class PageData {
                [string] $Title
                [string] $BaseUrl
                [string[]] $ImagesUrl
                PageData([string]$title, [string]$baseUrl, [string[]]$images){
                    $this.Title = $title
                    $this.BaseUrl = $baseUrl
                    $this.ImagesUrl = $images
                }
            }
            function Get-ImagesUrlFromPage {
                param([Parameter(Mandatory)][string] $PageUrl)
                return Invoke-WebRequest $PageUrl | Select-HtmlContent "img", @{
                    src = [AngleParse.Attr]::Src
                } | ? { !([string]$_.src).Contains("counter_img.php?id=50") } | % { $_.src }
            }

            $imgs = Get-ImagesUrlFromPage -PageUrl $_.Href
            $page = New-Object PageData($_.Title, $_.Href, $imgs)
            return @{ Url = $_.Href; Page = $page }
        }

        foreach ($x in @($fetched)) {
            $fetchedByUrl[[string]$x.Url] = $x.Page
        }
    }

    $obj = for ($i = 0; $i -lt $list.Count; $i++) {
        $href = [string]$list[$i].href
        if ($fetchedByUrl.ContainsKey($href)) {
            $fetchedByUrl[$href]
        } elseif ($existingByUrl.ContainsKey($href)) {
            # Titleだけ更新された場合に追随（ImagesUrlは既存維持）
            $e = $existingByUrl[$href]
            $t = [string]$list[$i].title
            if ($null -ne $t -and $t -ne "" -and $e.Title -ne $t) {
                $e.Title = $t
            }
            $e
        } else {
            $null
        }
    }

    if (@($obj | ? { $_ -eq $null }).Count -gt 0) {
        Write-Warning "Diff mode produced gaps (missing entries). fall back to FullFetch."
        $FullFetch = $true
        $obj = 0..($list.count -1) | % -parallel -ThrottleLimit $ThrottleLimit {
            Import-Module AngleParse
            class PageData {
                [string] $Title
                [string] $BaseUrl
                [string[]] $ImagesUrl
                PageData([string]$title, [string]$baseUrl, [string[]]$images){
                    $this.Title = $title
                    $this.BaseUrl = $baseUrl
                    $this.ImagesUrl = $images
                }
            }
            function Get-ImagesUrlFromPage {
                param([Parameter(Mandatory)][string] $PageUrl)
                return Invoke-WebRequest $PageUrl | Select-HtmlContent "img", @{
                    src = [AngleParse.Attr]::Src
                } | ? { !([string]$_.src).Contains("counter_img.php?id=50") } | % { $_.src }
            }

            $imgs = Get-ImagesUrlFromPage -PageUrl ($using:list)[$_].href
            $result = New-Object PageData(($using:list)[$_].title, ($using:list)[$_].href, $imgs)
            return @{
                Index = $_
                Page = $result
            }
        } | Sort-Object -Property Index | % { $_.Page }
    }
}

$obj | ConvertTo-Json | Out-File $OutFile -Encoding utf8
$obj
