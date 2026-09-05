$ErrorActionPreference = "Continue"

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  !! $msg" -ForegroundColor Red }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    Write-Fail "Lance ce script en tant qu'Administrateur."
    pause; exit 1
}

# Mots de passe forts
$chars = (48..57) + (65..90) + (97..122)
$mdpWifi = -join ($chars | Get-Random -Count 20 | ForEach-Object { [char]$_ })
$mdpUser = -join ($chars | Get-Random -Count 16 | ForEach-Object { [char]$_ })
$ssid        = "Miguation"
$nomPartage  = "mgx-share"
$tempUser    = "mgx-tmp"

$hotspotDemarre = $false
$partageOK      = $false
$userOK         = $false

function Stop-Tout {
    if ($partageOK)      { net share $nomPartage /delete 2>$null | Out-Null }
    if ($userOK)         { Remove-LocalUser -Name $tempUser -ErrorAction SilentlyContinue }
    if ($hotspotDemarre) {
        try { netsh wlan stop hostednetwork 2>$null | Out-Null } catch {}
        try {
            $null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]
            $profile = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()
            if ($profile) {
                $mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)
                $mgr.StopTetheringAsync().AsTask().Wait()
            }
        } catch {}
    }
}

try {
    Write-Step "Exportation en cours..."
    $exportDossier = & "$PSScriptRoot\export.ps1" -Destination "$env:TEMP\miguation-wifi"

    if (-not $exportDossier -or ($exportDossier -is [array])) {
        $exportDossier = Get-ChildItem "$env:TEMP\miguation-wifi" -Directory |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $exportDossier -or -not (Test-Path $exportDossier)) {
        Write-Fail "L'exportation a echoue - dossier introuvable."
        pause; exit 1
    }
    Write-OK "Export dans : $exportDossier"

    # Hotspot
    Write-Step "Creation du hotspot WiFi..."
    $hotspotOK = $false

    # Methode 1 : WinRT
    try {
        $null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]
        $profile = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()
        if ($profile) {
            $mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)
            $cfg = $mgr.GetCurrentAccessPointConfiguration()
            $cfg.Ssid = $ssid
            $cfg.Passphrase = $mdpWifi
            $mgr.ConfigureAccessPointAsync($cfg).AsTask().Wait()
            $result = $mgr.StartTetheringAsync().AsTask().Result
            if ($result.Status -eq 0) {
                $hotspotOK = $true
                $hotspotDemarre = $true
                Write-OK "Hotspot demarre (API moderne)"
            }
        }
    } catch {}

    # Methode 2 : netsh
    if (-not $hotspotOK) {
        netsh wlan set hostednetwork mode=allow ssid="$ssid" key="$mdpWifi" 2>$null | Out-Null
        $r = netsh wlan start hostednetwork 2>&1
        if ($r -match "demarre|started") {
            $hotspotOK = $true
            $hotspotDemarre = $true
            Write-OK "Hotspot demarre (netsh)"
        }
    }

    # Methode 3 : guide manuel
    if (-not $hotspotOK) {
        Write-Host ""
        Write-Host "  Hotspot automatique impossible sur cet adaptateur." -ForegroundColor Yellow
        Write-Host "  Active-le manuellement :" -ForegroundColor Yellow
        Write-Host "  Parametres Windows > Reseau > Point d'acces mobile" -ForegroundColor Yellow
        Write-Host "  SSID : $ssid   |   Mot de passe : $mdpWifi" -ForegroundColor Yellow
        Read-Host "  Appuie sur Entree quand le hotspot est actif"
        $hotspotDemarre = $true
    }

    # Utilisateur temporaire
    Write-Step "Creation du partage securise..."
    $secPass = ConvertTo-SecureString $mdpUser -AsPlainText -Force
    New-LocalUser -Name $tempUser -Password $secPass -Description "Miguation temp" `
        -PasswordNeverExpires -AccountNeverExpires -ErrorAction Stop | Out-Null
    $userOK = $true

    net share "$nomPartage=$exportDossier" /GRANT:"$tempUser,READ" 2>$null | Out-Null
    $partageOK = $true
    Write-OK "Partage cree (utilisateur temporaire isole)"

    # Afficher les infos
    Write-Host ""
    Write-Host "  +====================================================+" -ForegroundColor Green
    Write-Host "  |   Sur le NOUVEAU PC - fais ces 2 choses :          |" -ForegroundColor Green
    Write-Host "  |                                                    |" -ForegroundColor Green
    Write-Host "  |   1. Connecte-toi au WiFi :                        |" -ForegroundColor Green
    Write-Host "  |      Nom      : $ssid" -ForegroundColor Yellow
    Write-Host "  |      Mot de passe WiFi    : $mdpWifi" -ForegroundColor Yellow
    Write-Host "  |                                                    |" -ForegroundColor Green
    Write-Host "  |   2. Lance transfert-wifi-client.bat               |" -ForegroundColor Green
    Write-Host "  |      Mot de passe partage : $mdpUser" -ForegroundColor Yellow
    Write-Host "  +====================================================+" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Laisse cette fenetre ouverte." -ForegroundColor White
    Write-Host "  Appuie sur Entree quand le nouveau PC a termine." -ForegroundColor White
    Read-Host

} finally {
    Write-Step "Nettoyage..."
    Stop-Tout
    Write-OK "Partage ferme, utilisateur supprime, hotspot eteint."
}
