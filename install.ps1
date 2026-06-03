# install-recovery-only.ps1
# Instalador Avell Recovery + One Control (SEM SDK)
# Para máquinas que já têm o SDK instalado ou não precisam dele
# Versão: FINAL - Baseado no AISTONE GX

# ==== Verificar privilégios ====
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Reabrindo como Administrador..." -ForegroundColor Yellow
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $PSCommandPath
$LogFile   = Join-Path $ScriptDir "install.log"

function Log {
    param([string]$msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host $msg -ForegroundColor Cyan
}

function Show-Error {
    param([string]$msg)
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Red
    Write-Host " OPS! ALGO DEU ERRADO" -ForegroundColor White
    Write-Host "=========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $msg -ForegroundColor Yellow
    Write-Host ""
    Write-Host "REINICIE O PROCESSO DE INSTALACAO." -ForegroundColor Yellow
    Write-Host "Se o erro persistir, verifique o arquivo install.log" -ForegroundColor Yellow
    Write-Host ""
    Log "ERRO: $msg"
    pause
    exit 1
}

function Retry-Action {
    param(
        [scriptblock]$Action,
        [int]$MaxAttempts = 3,
        [string]$ActionName = "Acao"
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Log ("Tentativa " + $attempt + " de " + $MaxAttempts + " para: " + $ActionName)
            & $Action
            Log ($ActionName + " concluida com sucesso na tentativa " + $attempt)
            return $true
        }
        catch {
            Log ("Tentativa " + $attempt + " falhou: " + $_.Exception.Message)
            if ($attempt -eq $MaxAttempts) {
                Log ("FALHA CRITICA: " + $ActionName + " falhou apos " + $MaxAttempts + " tentativas")
                throw $_
            }
            else {
                Log "Aguardando 5 segundos antes da proxima tentativa..."
                Start-Sleep -Seconds 5
            }
        }
    }
    return $false
}

function Test-OneControlInstalled {
    $localAppData = [Environment]::GetFolderPath("LocalApplicationData")
    $ocPath = Join-Path $localAppData "Programs\Avell One Control\Avell One Control.exe"

    if (Test-Path $ocPath) {
        Log "One Control detectado em: $ocPath"
        return $true
    }

    $ocReg = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -like "*One Control*" }
    if (-not $ocReg) {
        $ocReg = Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "*One Control*" }
    }
    if ($ocReg) {
        Log "One Control detectado pelo registro: $($ocReg.DisplayName)"
        return $true
    }

    return $false
}

Clear-Host
Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host " AVELL RECOVERY + ONE CONTROL" -ForegroundColor White
Write-Host " (Instalacao sem SDK)" -ForegroundColor White
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""

Log "===== Inicio da instalacao (Recovery + One Control) ====="
Log "Diretorio: $ScriptDir"

# ==== AVISO INICIAL - CONECTIVIDADE (15s AUTOMATICO) ====
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "                                                                " -ForegroundColor Cyan
Write-Host "              ATENCAO - CONECTIVIDADE NECESSARIA                " -ForegroundColor Yellow
Write-Host "                                                                " -ForegroundColor Cyan
Write-Host "  Para o pleno funcionamento do AVELL One Control,             " -ForegroundColor White
Write-Host "  recomenda-se que voce conecte seu cabo de rede ou            " -ForegroundColor White
Write-Host "  esteja conectado a uma rede Wi-Fi antes de prosseguir.       " -ForegroundColor White
Write-Host "                                                                " -ForegroundColor Cyan
Write-Host "  Continuando automaticamente em 15 segundos...                " -ForegroundColor Green
Write-Host "                                                                " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Log "Exibindo aviso de conectividade (15 segundos automatico)..."

$timeout   = 15
$startTime = Get-Date

while (((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
    Start-Sleep -Milliseconds 100
}

Log "Timeout de 15 segundos atingido. Continuando instalacao..."

Write-Host ""
Write-Host "Iniciando instalacao..." -ForegroundColor Green
Write-Host ""
Start-Sleep -Seconds 2

# ==== Definir arquivos ====
$OcExe      = Join-Path $ScriptDir "OC56.exe"
$WinPeWim   = Join-Path $ScriptDir "winpe.wim"

# ==== 1. Verificar arquivos ====
Write-Host ""
Write-Host "[1/7] Verificando arquivos necessarios..." -ForegroundColor Yellow

if (-not (Test-Path $OcExe)) {
    Show-Error "Arquivo nao encontrado: $OcExe"
}
if (-not (Test-Path $WinPeWim)) {
    Show-Error "Arquivo nao encontrado: $WinPeWim"
}

Log "Todos os arquivos necessarios foram encontrados."

# ==== 2. Reduzir C: em 30GB e criar particao R: (COM 3 TENTATIVAS) ====
Write-Host ""
Write-Host "[2/7] Verificando/criando particao de recuperacao R: (ate 3 tentativas)..." -ForegroundColor Yellow

$RecoverySizeMB = 30720

$partitionAction = {
    $existingR = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -eq "R" }
    if ($existingR) {
        Log "Particao R: ja existe. Pulando criacao."
        return
    }

    Log "Particao R: nao encontrada. Criando..."
    $cVolume = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -eq "C" }
    if (-not $cVolume) {
        throw "Nao foi possivel localizar o volume C:."
    }
    $cPartition = Get-Partition -DriveLetter C -ErrorAction Stop
    $diskNumber = $cPartition.DiskNumber
    Log "Volume C: esta no disco $diskNumber."

    $minFreeMB = 35000
    if ($cVolume.SizeRemaining / 1MB -lt $minFreeMB) {
        throw "Espaco livre insuficiente em C:. Necessario: 35GB | Disponivel: {0:N2} GB" -f ($cVolume.SizeRemaining/1GB)
    }

    $diskpartScript  = Join-Path $env:TEMP "diskpart_recovery_shrink.txt"
    $diskpartContent = @"
select volume C
shrink desired=$RecoverySizeMB
select disk $diskNumber
create partition primary size=$RecoverySizeMB
format fs=ntfs quick label=RECOVERY
assign letter=R
"@
    $diskpartContent | Out-File -FilePath $diskpartScript -Encoding ASCII -Force

    Log "Executando Diskpart para SHRINK C: e criar particao R:..."
    & diskpart.exe /s "$diskpartScript" | Out-File -FilePath $LogFile -Append
    Remove-Item $diskpartScript -Force -ErrorAction SilentlyContinue

    Log "Diskpart finalizado. Aguardando montagem da unidade R:..."
    $timeout = 60
    $ok      = $false
    for ($i = 1; $i -le $timeout; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Path "R:\") {
            $ok = $true
            Log "R: montado apos $i segundo(s)."
            break
        }
    }

    if (-not $ok) {
        Log "R: nao apareceu. Tentando forcar atribuicao..."
        $diskpartScript = Join-Path $env:TEMP "diskpart_recovery_forceR.txt"
        $forceContent   = @"
select volume last
assign letter=R
"@
        $forceContent | Out-File -FilePath $diskpartScript -Encoding ASCII -Force
        & diskpart.exe /s "$diskpartScript" | Out-File -FilePath $LogFile -Append
        Remove-Item $diskpartScript -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }

    if (-not (Test-Path "R:\")) {
        throw "Particao R: nao esta acessivel apos criacao."
    }

    Log "Verificacao: Particao R: acessivel."
}

try {
    Retry-Action -Action $partitionAction -MaxAttempts 3 -ActionName "Criacao da particao R:"
}
catch {
    Show-Error "Falha ao criar particao R: apos 3 tentativas. Detalhes: $($_.Exception.Message)"
}

# ==== 3. Ocultar R: no Explorer ====
Write-Host ""
Write-Host "[3/7] Verificando/ocultando particao R: no Explorer..." -ForegroundColor Yellow
try {
    $regPath    = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $existingKey = Get-ItemProperty -Path $regPath -Name "NoDrives" -ErrorAction SilentlyContinue

    if ($existingKey -and $existingKey.NoDrives -eq 131072) {
        Log "Particao R: ja esta oculta no Explorer. Pulando."
    }
    else {
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        New-ItemProperty -Path $regPath -Name "NoDrives" -Value 131072 -PropertyType DWord -Force | Out-Null
        Log "Particao R: oculta no Explorer."
        $verify = Get-ItemProperty -Path $regPath -Name "NoDrives" -ErrorAction Stop
        if ($verify.NoDrives -ne 131072) {
            throw "Falha ao ocultar R: no registro."
        }
        Log "Verificacao: R: ocultado com sucesso."
    }
}
catch {
    Show-Error "Falha ao ocultar particao R: $($_.Exception.Message)"
}

# ==== 4. Aplicar WinPE em R: (COM 3 TENTATIVAS) ====
Write-Host ""
Write-Host "[4/7] Verificando/aplicando WinPE na particao R: (ate 3 tentativas)..." -ForegroundColor Yellow

$winpeAction = {
    $winpeCheck = Test-Path "R:\Windows\avell-recovery\avell-recovery.exe" -ErrorAction SilentlyContinue
    if ($winpeCheck) {
        Log "WinPE ja esta aplicado em R:. Pulando."
        return
    }

    Log "Aplicando WinPE em R: (pode demorar, contem recovery completo)..."
    $args = @(
        "/Apply-Image",
        "/ImageFile:`"$WinPeWim`"",
        "/Index:1",
        "/ApplyDir:R:\"
    )
    Log ("Executando: dism.exe " + ($args -join ' '))
    $process = Start-Process -FilePath "dism.exe" -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        throw "DISM retornou erro: $($process.ExitCode)"
    }
    Log "WinPE aplicado com sucesso."
    if (-not (Test-Path "R:\Windows")) {
        throw "Pasta R:\Windows nao foi criada apos aplicacao do WinPE."
    }
    Log "Verificacao: WinPE aplicado corretamente (windows.wim ja esta embutido)."
}

try {
    Retry-Action -Action $winpeAction -MaxAttempts 3 -ActionName "Aplicacao do WinPE"
}
catch {
    Show-Error "Falha ao aplicar WinPE apos 3 tentativas. Detalhes: $($_.Exception.Message)"
}

# ==== 5. Criar entrada de boot "Recuperar-Windows-Avell" (PERSISTENTE via GUID) ====
Write-Host ""
Write-Host "[5/7] Criando entrada de boot..." -ForegroundColor Yellow

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

# ==== 6. Ajustar BCD para boot direto (timeout=0, sem menu) ====
Write-Host ""
Write-Host "[6/7] Ajustando BCD para boot direto (menu so em caso de crash)..." -ForegroundColor Yellow

try {
    Log "Definindo timeout do boot para 0 (boot direto no sistema padrao)..."
    $timeoutProcess = Start-Process -FilePath "bcdedit.exe" -ArgumentList "/timeout","0" -Wait -PassThru -NoNewWindow

    if ($timeoutProcess.ExitCode -eq 0) {
        Log "Timeout do boot definido para 0."
    }
    else {
        Log "AVISO: Falha ao definir timeout (codigo: $($timeoutProcess.ExitCode))."
    }

    Log "Desativando exibicao forcada do menu de boot..."
    $displayProcess = Start-Process -FilePath "bcdedit.exe" -ArgumentList "/set","{bootmgr}","displaybootmenu","no" -Wait -PassThru -NoNewWindow

    if ($displayProcess.ExitCode -eq 0) {
        Log "Exibicao forcada do menu de boot desativada."
    }
    else {
        Log "AVISO: Falha ao desativar displaybootmenu (codigo: $($displayProcess.ExitCode))."
    }

    Log "Reconfirmando Windows 11 como entrada padrao..."
    & bcdedit /default "{current}" | Out-Null

    Log "Ajustes de BCD aplicados com sucesso (boot direto, menu so via teclas de boot ou crash)."
}
catch {
    Log "AVISO: Falha ao ajustar timeout/displaybootmenu no BCD: $($_.Exception.Message)"
}

# ==== 7. Instalar One Control (5 TENTATIVAS) ====
Write-Host ""
Write-Host "[7/7] Verificando/instalando One Control (modo silencioso, ate 5 tentativas)..." -ForegroundColor Yellow

try {
    if (Test-OneControlInstalled) {
        Log "One Control ja esta instalado. Pulando etapa."
    }
    else {
        Log "One Control nao detectado. Iniciando instalacao silenciosa..."

        $ocDir  = Split-Path $OcExe
        $ocName = Split-Path $OcExe -Leaf

        if (-not (Test-Path $OcExe)) {
            throw "OC56.exe nao encontrado em: $OcExe"
        }

        $maxAttempts = 5
        $installed = $false

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            Log ("Tentativa " + $attempt + " de " + $maxAttempts + " para instalacao do One Control...")

            Push-Location $ocDir

            Get-Process -Name "OC56","setup","Avell*","Custom*","Control*","One Control" -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction SilentlyContinue

            Start-Sleep -Seconds 3

            $args = @(
                "/S",
                "/silent",
                "/VERYSILENT",
                "/SUPPRESSMSGBOXES",
                "/NORESTART"
            )
            Log ("Executando OC (silent): .\$ocName " + ($args -join ' '))
            $proc = Start-Process -FilePath ".\$ocName" -ArgumentList $args -PassThru

            $maxWait = 90
            $elapsed = 0
            while (-not $proc.HasExited -and $elapsed -lt $maxWait) {
                Start-Sleep -Seconds 3
                $elapsed += 3
            }

            if (-not $proc.HasExited) {
                Log ("AVISO: Instalador OC ainda em execucao apos " + $maxWait + "s. Encerrando processo...")
                try { $proc.Kill() } catch { }
            }

            $exitCode = $proc.ExitCode
            Log ("Instalador One Control terminou com codigo: " + $exitCode)

            Pop-Location

            Start-Sleep -Seconds 10

            if (Test-OneControlInstalled) {
                Log ("Verificacao: One Control instalado com sucesso na tentativa " + $attempt + ".")
                $installed = $true
                break
            }
            else {
                if ($exitCode -eq -1073741819) {
                    Log ("AVISO: Instalador retornou codigo 0xC0000005 (ACCESS VIOLATION) na tentativa " + $attempt + ".")
                    if ($attempt -lt $maxAttempts) {
                        Log "Aguardando 5 segundos antes da proxima tentativa..."
                        Start-Sleep -Seconds 5
                    }
                }
                elseif ($exitCode -eq 0) {
                    Log ("AVISO: Instalador retornou codigo 0 (sucesso), mas One Control nao foi detectado na tentativa " + $attempt + ".")
                    if ($attempt -lt $maxAttempts) {
                        Log "Aguardando 5 segundos antes da proxima tentativa..."
                        Start-Sleep -Seconds 5
                    }
                }
                else {
                    Log ("AVISO: Instalador retornou codigo " + $exitCode + " na tentativa " + $attempt + ".")
                    if ($attempt -lt $maxAttempts) {
                        Log "Aguardando 5 segundos antes da proxima tentativa..."
                        Start-Sleep -Seconds 5
                    }
                }
            }
        }

        if ($installed) {
            Log ("One Control instalado com sucesso apos " + $attempt + " tentativa(s).")
        }
        else {
            Log ("AVISO CRITICO: One Control NAO foi detectado apos " + $maxAttempts + " tentativas.")
            Write-Host ""
            Write-Host "=========================================" -ForegroundColor Red
            Write-Host " AVISO: ONE CONTROL NAO INSTALOU" -ForegroundColor Yellow
            Write-Host "=========================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "O One Control nao foi instalado com sucesso." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "SOLUCOES:" -ForegroundColor Cyan
            Write-Host "1. Instale manualmente o arquivo OC56.exe" -ForegroundColor White
            Write-Host "2. Execute novamente este instalador" -ForegroundColor White
            Write-Host ""
            Write-Host "Pressione qualquer tecla para continuar o reinicio..." -ForegroundColor Green
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }

        Get-Process -Name "Avell One Control","OneControl","AvellOneControl" -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Log "Processos do One Control finalizados (se estavam em execucao)."
    }
}
catch {
    Log "AVISO: Erro na instalacao do One Control: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "AVISO: One Control pode nao ter sido instalado corretamente." -ForegroundColor Yellow
    Write-Host ""
}

# ==== 8. Reiniciar ====
Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host " INSTALACAO CONCLUIDA COM SUCESSO!" -ForegroundColor White
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Log "Instalacao concluida. Reiniciando em 10 segundos..."
Start-Sleep -Seconds 10
Restart-Computer -Force
