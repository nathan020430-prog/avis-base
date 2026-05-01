# Mini static file server (PowerShell, no deps)
# Usage: powershell -ExecutionPolicy Bypass -File .claude\serve.ps1 -Port 8080
param(
  [int]$Port = 8080,
  [string]$Root = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)

$mimeTypes = @{
  '.html' = 'text/html; charset=utf-8'
  '.htm'  = 'text/html; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.js'   = 'application/javascript; charset=utf-8'
  '.mjs'  = 'application/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.svg'  = 'image/svg+xml'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.gif'  = 'image/gif'
  '.webp' = 'image/webp'
  '.ico'  = 'image/x-icon'
  '.woff' = 'font/woff'
  '.woff2'= 'font/woff2'
  '.ttf'  = 'font/ttf'
  '.txt'  = 'text/plain; charset=utf-8'
  '.md'   = 'text/markdown; charset=utf-8'
}

try {
  $listener.Start()
  Write-Host "Avis Basé dev server"
  Write-Host "  Root : $Root"
  Write-Host "  URL  : $prefix"
  Write-Host "  Stop : Ctrl+C"
  Write-Host ""

  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response

    try {
      $relPath = [System.Uri]::UnescapeDataString($req.Url.LocalPath).TrimStart('/').Replace('/', '\')
      if (-not $relPath -or $relPath -eq '\') { $relPath = 'index.html' }

      # Bloque path traversal
      if ($relPath -match '\.\.') {
        $res.StatusCode = 400
        $res.OutputStream.Close()
        continue
      }

      $file = Join-Path $Root $relPath

      # Auto index.html sur dossiers
      if ((Test-Path $file -PathType Container)) {
        $candidate = Join-Path $file 'index.html'
        if (Test-Path $candidate -PathType Leaf) { $file = $candidate }
      }

      if (Test-Path $file -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $ext = [System.IO.Path]::GetExtension($file).ToLower()
        $mime = $mimeTypes[$ext]
        if (-not $mime) { $mime = 'application/octet-stream' }
        $res.ContentType = $mime
        $res.ContentLength64 = $bytes.Length
        $res.Headers.Add('Cache-Control', 'no-store, must-revalidate')
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
        $code = 200
      } else {
        $res.StatusCode = 404
        $body = [System.Text.Encoding]::UTF8.GetBytes("<h1>404</h1><p>Not found: $relPath</p>")
        $res.ContentType = 'text/html; charset=utf-8'
        $res.ContentLength64 = $body.Length
        $res.OutputStream.Write($body, 0, $body.Length)
        $code = 404
      }
      Write-Host ("[{0}] {1} {2} {3}" -f (Get-Date -Format 'HH:mm:ss'), $code, $req.HttpMethod, $req.Url.PathAndQuery)
    } catch {
      Write-Host "ERROR handling request: $($_.Exception.Message)"
      $res.StatusCode = 500
    } finally {
      try { $res.OutputStream.Close() } catch {}
    }
  }
} finally {
  if ($listener.IsListening) { $listener.Stop() }
  $listener.Close()
}
