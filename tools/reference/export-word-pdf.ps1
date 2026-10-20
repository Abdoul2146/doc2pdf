<#
  export-word-pdf.ps1

  Dev-only ground-truth generator. Drives the locally installed Microsoft Word
  via COM automation to export .doc/.docx fixtures to PDF, exactly the way
  Word's own "Save As PDF" / ExportAsFixedFormat path does. Nothing here ships
  in the Android app; it exists purely so the renderer can be diffed against a
  real Word reference.

  Usage:
    powershell -ExecutionPolicy Bypass -File tools/reference/export-word-pdf.ps1 `
      -Docs "docA.docx","docB.docx" -OutDir "tools/reference/out"

  wdExportFormatPDF = 17
#>
param(
  [Parameter(Mandatory = $true)][string[]]$Docs,
  [Parameter(Mandatory = $true)][string]$OutDir
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $OutDir)) {
  New-Item -ItemType Directory -Path $OutDir | Out-Null
}
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$word.AutomationSecurity = 3  # msoAutomationSecurityForceDisable (no macro prompts)
$word.Options.ConfirmConversions = $false

try {
  foreach ($d in $Docs) {
    $src = (Resolve-Path -LiteralPath $d).Path
    $name = [System.IO.Path]::GetFileNameWithoutExtension($src)
    $pdf = Join-Path $OutDir ($name + '.pdf')

    Write-Host "Exporting: $src"
    $doc = $word.Documents.Open($src, $false, $true)  # ConfirmConversions, ReadOnly
    try {
      $doc.ExportAsFixedFormat($pdf, 17)  # 17 = wdExportFormatPDF
    }
    finally {
      $doc.Close(0)  # wdDoNotSaveChanges
    }

    if (Test-Path -LiteralPath $pdf) {
      Write-Host ("  OK  {0} bytes -> {1}" -f (Get-Item -LiteralPath $pdf).Length, $pdf)
    }
    else {
      Write-Host "  FAILED: no PDF produced"
    }
  }
}
finally {
  $word.Quit()
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
