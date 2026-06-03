# boot_config.ps1
# Passos 6, 7 e 8 - Configuracao de boot

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $PSCommandPath
$LogFile   = Join-Path $ScriptDir "install.log"

function Log {
    param([string]$msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host $msg -ForegroundColor Cyan
}

Write-Host ""
Write-Host "[6/9] Criando entrada de boot..." -ForegroundColor Yellow

try {
    Log "Obtendo GUID da particao R:..."
    $partition = Get-Partition -DriveLetter R -ErrorAction Stop
    $partitionGuid = $partition.Guid

    if (-not $partitionGuid) {
        Log "AVISO: Nao foi possivel obter GUID da particao R:. Pulando."
    } else {
        Log "GUID da particao R: = $partitionGuid"

        Log "Executando bcdboot R:\Windows..."
        $process = Start-Process -FilePath "bcdboot.exe" -ArgumentList "R:\Windows" -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) {
            Log "AVISO: bcdboot retornou codigo $($process.ExitCode), prosseguindo..."
        }

        Start-Sleep -Seconds 3

        Log "Procurando entrada de boot em partition=R:..."
        $bcdText = & bcdedit /enum | Out-String

        $splitKeyword = if ($bcdText -match "Carregador de Inic") { "Carregador de Inic" } else { "Windows Boot Loader" }
        $blocks = $bcdText -split $splitKeyword
        $recoveryId = $null

        foreach ($rawBlock in $blocks) {
            $block = $splitKeyword + $rawBlock
            if ($block -notmatch "partition=R:") { continue }
            foreach ($line in ($block -split "`r?`n")) {
                if ($line -match "^\s*(identifier|identificador)\s+(\{[^\}]+\})") {
                    $recoveryId = $matches[2]
                    Log "Entrada encontrada. Identificador = $recoveryId"
                    break
                }
            }
            if ($recoveryId) { break }
        }

        if (-not $recoveryId) {
            Log "AVISO: Entrada com partition=R: nao encontrada no BCD. Pulando."
        } else {
            $cleanGuid = $partitionGuid -replace '[{}]', ''
            & bcdedit /set $recoveryId device "partition={$cleanGuid}" | Out-Null
            & bcdedit /set $recoveryId osdevice "partition={$cleanGuid}" | Out-Null
            & bcdedit /set $recoveryId description "Recuperar-Windows-Avell" | Out-Null
            & bcdedit /set $recoveryId detecthal yes | Out-Null
            & bcdedit /set $recoveryId winpe yes | Out-Null
            & bcdedit /set $recoveryId ems no | Out-Null
            & bcdedit /default "{current}" | Out-Null
            Log "Entrada de boot criada com sucesso."
        }
    }
} catch {
    Log "AVISO: Falha no passo 6: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "[7/9] Ajustando BCD para boot direto..." -ForegroundColor Yellow

try {
    & bcdedit /timeout 0 | Out-Null
    Log "Timeout do boot definido para 0."

    & bcdedit /set "{bootmgr}" displaybootmenu no | Out-Null
    Log "Menu de boot desativado."

    & bcdedit /default "{current}" | Out-Null
    Log "Ajustes de BCD aplicados com sucesso."
} catch {
    Log "AVISO: Falha no passo 7: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "[8/9] Removendo atalhos..." -ForegroundColor Yellow

$shortcutPaths = @(
    (Join-Path $env:USERPROFILE "Desktop\Avell Custom Control.lnk"),
    (Join-Path $env:PUBLIC "Desktop\Avell Custom Control.lnk"),
    "C:\Users\Public\Desktop\Avell Custom Control.lnk"
)

foreach ($path in $shortcutPaths) {
    if (Test-Path $path) {
        try {
            Remove-Item $path -Force -ErrorAction Stop
            Log "Atalho removido: $path"
        } catch {
            Log "AVISO: Nao foi possivel remover $path"
        }
    }
}

Write-Host ""
Write-Host "BOOT CONFIG CONCLUIDO" -ForegroundColor Green
Log "BOOT CONFIG CONCLUIDO"

# ==== REINICIO ====
Log "Reiniciando o sistema em 10 segundos..."
Start-Sleep -Seconds 10
Restart-Computer -Force
