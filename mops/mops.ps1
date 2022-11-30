[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $OutFile = "./update-info.dat",
    [switch]
    $ForceCheck,
    [switch]
    $SkipFeedGen
)

Import-Module AngleParse

#アップデートのチェック
$check = & $PSScriptRoot/check-update.ps1 -NoSaveHashFile -OutFile $OutFile

if ($check -or $ForceCheck){
    # アップデートがある or 更新にかかわらず強制実行する場合の処理

    & $PSScriptRoot/update-json.ps1 -Debug
    & $PSScriptRoot/patch-json.ps1 -Debug
    & $PSScriptRoot/generate-4komaDataJs.ps1 -Debug
    #& $PSScriptRoot/download-img.ps1 -OnlyRecently
    #& $PSScriptRoot/generate-webp.ps1 -OnlyRecently -Debug
    
    if (!$SkipFeedGen){
        #NOTE: 現状は4komaData.jsonを自動生成しないのでReturnNewContentOnlyオプションで最短実行する
        $newContent = & $PSScriptRoot/update-json.ps1 -ReturnNewContentOnly -Debug
        Write-Debug "new-content: $($newContent | ConvertTo-Json)"
        & $PSScriptRoot/update-feed.ps1 -DataObject $newContent -Debug
        $check.Hash | Out-File $OutFile -Encoding utf8 -NoNewline    
    }

    return $true

}else{
    Write-Debug "Has not update."

    return $false
}


