# Bottleneck.PDF.ps1
# PDF generation utilities

function ConvertTo-BottleneckPDF {
    param(
        [Parameter(Mandatory)][string]$HtmlContent,
        [Parameter(Mandatory)][string]$OutputPath
    )

    # Create a temporary HTML file
    $tempHtml = [System.IO.Path]::GetTempFileName() + ".html"
    $HtmlContent | Set-Content $tempHtml

    try {
        # Use wkhtmltopdf if available, otherwise use Chrome/Edge headless
        $wkhtmltopdf = Get-Command wkhtmltopdf -ErrorAction SilentlyContinue
        $chrome = Get-Command "chrome.exe" -ErrorAction SilentlyContinue
        $edge = Get-Command "msedge.exe" -ErrorAction SilentlyContinue

        if ($wkhtmltopdf) {
            & wkhtmltopdf $tempHtml $OutputPath 2>&1 | Out-Null
        } elseif ($edge) {
            $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
            & $edgePath --headless --disable-gpu --print-to-pdf="$OutputPath" $tempHtml 2>&1 | Out-Null
        } elseif ($chrome) {
            & chrome.exe --headless --disable-gpu --print-to-pdf="$OutputPath" $tempHtml 2>&1 | Out-Null
        } else {
            # Fallback: Use Word COM object if available
            try {
                $word = New-Object -ComObject Word.Application
                $word.Visible = $false
                $doc = $word.Documents.Open($tempHtml)
                $doc.SaveAs([ref]$OutputPath, [ref]17) # 17 = wdFormatPDF
                $doc.Close()
                $word.Quit()
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($word) | Out-Null
            } catch {
                Write-Warning "No PDF converter found. Install wkhtmltopdf or use Edge/Chrome."
                return $false
            }
        }
        return $true
    } finally {
        Remove-Item $tempHtml -ErrorAction SilentlyContinue
    }
}
