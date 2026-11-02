<#
.SYNOPSIS
Runs CloudPulse on minikube in Windows 11 (PowerShell).
Does NOT require make, bash, openssl, and envsubst. Works with Windows PowerShell 5.1 and PowerShell 7.

.DESCRIPTION
What it does (PowerShell equivalent of the flow in the Makefile):
0. Checks Docker; starts minikube with appropriate resources if not running
1. Generates random secrets into the .secrets.env file (excluded from git)
2. Builds the images using local Docker and loads them into the cluster with "minikube image load"
3. Creates namespace + ConfigMap + Secret using Terraform
4. Deploys MySQL, Redis, MinIO, the migration Job, web, and worker using kubectl

.PARAMETER Action
up      Sets up everything from scratch (build + load + Terraform + kubectl)  [default]
deploy  Deploys without building: for ready (e.g., GHCR) images with -ImageRepo and -ImageTag
forward Opens the application at http://localhost:8080 (stop with Ctrl+C)
status  Shows Pod, Service, and HPA status
logs    Monitors the logs of Web Pods
diagnose For 500 errors, etc.: pod status, php-fpm errors, MySQL replication, Vite files
down    Terraform destroy: deletes the namespace and everything inside it (cluster remains)
destroy Deletes the minikube cluster itself (minikube delete)

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\minikube.ps1 up

.EXAMPLE
$env:GHCR_USERNAME = 'user';$env:GHCR_PAT = ''
powershell -ExecutionPolicy Bypass -File .\minikube.ps1 deploy -ImageRepo ghcr.io/user/cloudpulse -ImageTag sha-abc1234
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('up', 'deploy', 'forward', 'status', 'logs', 'diagnose', 'down', 'destroy')]
    [string]$Action = 'up',

    
    [string]$Context = 'minikube',
    [string]$Namespace = 'cloudpulse',
    [int]$LocalPort = 8080,

    
    [string]$ImageRepo = 'cloudpulse',
    [string]$ImageTag = '',

    
    [string]$MinioImage = 'cgr.dev/chainguard/minio:latest',

    
    [int]$Cpus = 4,
    [int]$Memory = 6144,

    
    [switch]$AutoApprove
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

$SecretsFile = Join-Path $PSScriptRoot '.secrets.env'
$TagFile = Join-Path $PSScriptRoot '.image-tag'
$TfDir = Join-Path $PSScriptRoot 'terraform'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)



function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}


function Run {
    $exe = $args[0]
    $rest = @()
    if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }
    & $exe @rest | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "'$exe $($rest -join ' ')' basarisiz oldu (cikis kodu $LASTEXITCODE)."
    }
}

function Kube {
    Run kubectl --context $Context --namespace $Namespace @args
}


function Invoke-Quiet {
    $exe = $args[0]
    $rest = @()
    if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $exe @rest 2>&1 | Out-Null
        return $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
}

function Test-Tools([string[]]$Names) {
    $hints = @{
        docker    = 'Docker Desktop kurun: https://www.docker.com/products/docker-desktop'
        minikube  = 'winget install Kubernetes.minikube'
        kubectl   = 'winget install Kubernetes.kubectl'
        terraform = 'winget install Hashicorp.Terraform'
    }
    $missing = @($Names | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    if ($missing.Count -gt 0) {
        foreach ($tool in $missing) {
            Write-Host "Eksik arac: $tool  ->  $($hints[$tool])" -ForegroundColor Red
        }
        throw 'Eksik araclari kurup (yeni bir terminal acarak) tekrar deneyin.'
    }
}

function Test-Docker {
    if ((Invoke-Quiet docker info) -ne 0) {
        throw "Docker calismiyor. Docker Desktop'i acin, 'Engine running' gorunene kadar bekleyin ve tekrar deneyin."
    }
}


function Start-Minikube {
    if ((Invoke-Quiet minikube status -p $Context) -eq 0) {
        Write-Step "minikube '$Context' zaten calisiyor"
        return
    }

    $mem = $Memory
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $raw = & docker info --format '{{.MemTotal}}' 2>$null
    $ErrorActionPreference = $previous
    $bytes = 0L
    if ([long]::TryParse(([string]$raw).Trim(), [ref]$bytes) -and $bytes -gt 0) {
        $availableMb = [int]($bytes / 1MB)
        $mem = [Math]::Min($Memory, $availableMb - 512)
        if ($mem -lt 3072) {
            throw "Docker'a yalnizca $availableMb MB ayrilmis; CloudPulse icin en az ~3.5 GB gerekir. %UserProfile%\.wslconfig dosyasina 'memory=8GB' yazip 'wsl --shutdown' ile Docker Desktop'u yeniden baslatin (README'ye bakin)."
        }
    }

    Write-Step "minikube baslatiliyor (cpus=$Cpus, memory=${mem}MB, driver=docker)"
    Run minikube start -p $Context --driver=docker "--cpus=$Cpus" "--memory=$mem"
}

function Test-Cluster {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & kubectl --context $Context get nodes 2>&1 | Out-Null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) {
        throw "'$Context' context'ine baglanilamadi. Once minikube'u baslatin:  minikube start -p $Context --driver=docker --cpus=4 --memory=6144"
    }
}



function New-RandomBytes([int]$Count) {
    $bytes = New-Object byte[] $Count
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return , $bytes
}

function New-Hex([int]$Count) {
    -join ((New-RandomBytes $Count) | ForEach-Object { $_.ToString('x2') })
}


function Initialize-Secrets {
    if (-not (Test-Path -LiteralPath $SecretsFile)) {
        Write-Step '.secrets.env uretiliyor (rastgele degerler; bu dosyayi ASLA commit etmeyin)'
        $lines = @(
            "APP_KEY=base64:$([Convert]::ToBase64String((New-RandomBytes 32)))",
            "DB_ROOT_PASSWORD=$(New-Hex 16)",
            "DB_PASSWORD=$(New-Hex 16)",
            "DB_REPLICATION_PASSWORD=$(New-Hex 16)",
            "REDIS_PASSWORD=$(New-Hex 16)",
            "MINIO_ROOT_USER=cp$(New-Hex 6)",
            "MINIO_ROOT_PASSWORD=$(New-Hex 16)"
        )
        [System.IO.File]::WriteAllText($SecretsFile, (($lines -join "`n") + "`n"), $Utf8NoBom)
    }

    $secrets = @{}
    foreach ($line in Get-Content -LiteralPath $SecretsFile) {
        if ($line -match '^\s*([A-Z0-9_]+)=(.*)$') { $secrets[$Matches[1]] = $Matches[2] }
    }
    foreach ($key in 'APP_KEY', 'DB_ROOT_PASSWORD', 'DB_PASSWORD', 'DB_REPLICATION_PASSWORD', 'REDIS_PASSWORD', 'MINIO_ROOT_USER', 'MINIO_ROOT_PASSWORD') {
        if (-not $secrets[$key]) { throw "$SecretsFile icinde $key eksik. Dosyayi silip betigi yeniden calistirin." }
    }
    return $secrets
}



function Build-Images {
    $tag = if ($ImageTag) { $ImageTag } else { 'local-' + (Get-Date -Format 'yyyyMMddHHmmss') }

    $sha = 'local'
    try {
        $value = & git rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $value) { $sha = $value }
    } catch { }

    Write-Step "Imajlar derleniyor: $ImageRepo-app:$tag ve $ImageRepo-web:$tag"
    Run docker build --target app --build-arg "APP_VERSION=$tag" --build-arg "APP_COMMIT_SHA=$sha" -t "$ImageRepo-app:$tag" .
    Run docker build --target web -t "$ImageRepo-web:$tag" .

    Write-Step "Imajlar minikube'a yukleniyor (birkac dakika surebilir)"
    Run minikube -p $Context image load "$ImageRepo-app:$tag"
    Run minikube -p $Context image load "$ImageRepo-web:$tag"

    [System.IO.File]::WriteAllText($TagFile, $tag, $Utf8NoBom)
    $script:BuiltTag = $tag
}


function Invoke-Terraform([string]$Verb) {
    $vars = @{
        TF_VAR_kube_context         = $Context
        TF_VAR_namespace            = $Namespace
        TF_VAR_app_key              = $script:Secrets.APP_KEY
        TF_VAR_db_root_password     = $script:Secrets.DB_ROOT_PASSWORD
        TF_VAR_db_password          = $script:Secrets.DB_PASSWORD
        TF_VAR_db_replication_password = $script:Secrets.DB_REPLICATION_PASSWORD
        TF_VAR_redis_password       = $script:Secrets.REDIS_PASSWORD
        TF_VAR_minio_root_user      = $script:Secrets.MINIO_ROOT_USER
        TF_VAR_minio_root_password  = $script:Secrets.MINIO_ROOT_PASSWORD
    }

   
    if ($env:GHCR_PAT) {
        if (-not $env:GHCR_USERNAME) { throw 'GHCR_PAT verildiyse GHCR_USERNAME de verilmeli.' }
        $vars['TF_VAR_create_image_pull_secret'] = 'true'
        $vars['TF_VAR_ghcr_username'] = $env:GHCR_USERNAME
        $vars['TF_VAR_ghcr_pat'] = $env:GHCR_PAT
    }

    try {
        foreach ($name in $vars.Keys) { Set-Item -Path "Env:$name" -Value $vars[$name] }

        Write-Step "Terraform: $Verb"
        Run terraform "-chdir=$TfDir" init -input=false

        $tfArgs = @("-chdir=$TfDir", $Verb)
        if ($AutoApprove) { $tfArgs += '-auto-approve' }
        Run terraform @tfArgs
    }
    finally {
        foreach ($name in $vars.Keys) { Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue }
    }
}


function Apply-Manifest([string]$File, [string[]]$Selector = @()) {
    $text = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot $File))
    foreach ($name in $script:Placeholders.Keys) {
        $text = $text.Replace('${' + $name + '}', [string]$script:Placeholders[$name])
    }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('cloudpulse-' + [System.IO.Path]::GetFileName($File))
    [System.IO.File]::WriteAllText($tmp, $text, $Utf8NoBom)
    try { Kube apply @Selector -f $tmp }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Deploy-Workloads([string]$Tag) {
    $script:Placeholders = @{
        IMAGE_APP   = "$ImageRepo-app:$Tag"
        IMAGE_WEB   = "$ImageRepo-web:$Tag"
        MINIO_IMAGE = $MinioImage
    }

    Write-Step 'Veri katmani: MySQL primary + replica, Redis, MinIO'
    Apply-Manifest 'k8s/mysql-statefulset.yaml'
    Apply-Manifest 'k8s/redis-deployment.yaml'
    Apply-Manifest 'k8s/minio-deployment.yaml'
    Kube rollout status statefulset/mysql-primary --timeout=300s
    Kube rollout status statefulset/mysql-replica --timeout=300s
    Kube rollout status deployment/redis --timeout=180s
    Kube rollout status deployment/minio --timeout=180s

   
    Write-Step "Veritabani migration'i (Job)"
    Kube delete job cloudpulse-migrate --ignore-not-found --wait=true
    Apply-Manifest 'k8s/laravel-deployment.yaml' @('-l', 'app.kubernetes.io/component=migrate')
    try {
        Kube wait --for=condition=complete job/cloudpulse-migrate --timeout=300s
    }
    catch {
        Write-Host 'Migration basarisiz oldu, son log satirlari:' -ForegroundColor Red
        Kube logs job/cloudpulse-migrate --tail=40
        throw
    }

    Write-Step 'Uygulama: web (nginx + php-fpm), worker, HPA, PDB'
    Apply-Manifest 'k8s/laravel-deployment.yaml' @('-l', 'app.kubernetes.io/component!=migrate')
    Kube rollout status deployment/cloudpulse-web --timeout=300s
    Kube rollout status deployment/cloudpulse-worker --timeout=180s
}

function Invoke-Diagnose {
    $ErrorActionPreference = 'Continue'
    $kc = @('--context', $Context, '--namespace', $Namespace)
    $mysqlCmd = "MYSQL_PWD=`$MYSQL_ROOT_PASSWORD mysql -uroot -e '{0}'"

    Write-Step '1/6 Pod ve Job durumu (hepsi Running/Ready ve migrate Complete olmali)'
    & kubectl @kc get 'pods,jobs' 2>&1 | Out-Host

    Write-Step '2/6 php-fpm son hata satirlari (500 nedeni genelde burada: "Base table or view not found", "Vite manifest" vb.)'
    & kubectl @kc logs -l app.kubernetes.io/name=cloudpulse-web -c php-fpm --prefix --tail=40 2>&1 | Out-Host

    Write-Step '3/6 MySQL replikasyonu (Replica_SQL_Running: Yes ve Last_SQL_Error bos olmali)'
    $sql = 'SHOW REPLICA STATUS\G'
    & kubectl @kc exec mysql-replica-0 -- bash -c ($mysqlCmd -f $sql) 2>&1 |
        Select-String -Pattern 'Source_Host|Replica_(IO|SQL)_Running:|Seconds_Behind_Source|Last_(IO|SQL)_Error:' |
        Out-Host

    Write-Step '4/6 Tablolar: primary'
    & kubectl @kc exec mysql-primary-0 -- bash -c ($mysqlCmd -f 'SHOW TABLES FROM cloudpulse') 2>&1 | Out-Host

    Write-Step '5/6 Tablolar: replica (file_uploads burada yoksa replikasyon kopuktur)'
    & kubectl @kc exec mysql-replica-0 -- bash -c ($mysqlCmd -f 'SHOW TABLES FROM cloudpulse') 2>&1 | Out-Host

    Write-Step '6/6 Derlenmis frontend dosyalari (manifest.json olmali)'
    & kubectl @kc exec deploy/cloudpulse-web -c php-fpm -- ls -la public/build 2>&1 | Out-Host
}



try {
    switch ($Action) {
        'up' {
            Test-Tools 'docker', 'minikube', 'kubectl', 'terraform'
            Test-Docker
            Start-Minikube
            Test-Cluster
            Write-Step 'metrics-server eklentisi (HPA icin)'
            Run minikube -p $Context addons enable metrics-server
            $script:Secrets = Initialize-Secrets
            Build-Images
            Invoke-Terraform 'apply'
            Deploy-Workloads $script:BuiltTag
            Write-Host ''
            Write-Host "CloudPulse hazir. Acmak icin:  .\minikube.ps1 forward   ->   http://localhost:$LocalPort" -ForegroundColor Green
        }
        'deploy' {
            Test-Tools 'kubectl', 'terraform'
            Test-Cluster
            $tag = $ImageTag
            if (-not $tag -and (Test-Path -LiteralPath $TagFile)) { $tag = (Get-Content -LiteralPath $TagFile -Raw).Trim() }
            if (-not $tag) { throw '-ImageTag verin (ornegin sha-abc1234) ya da once "up" calistirin.' }
            $script:Secrets = Initialize-Secrets
            Invoke-Terraform 'apply'
            Deploy-Workloads $tag
            Write-Host ''
            Write-Host "Dagitim tamam ($ImageRepo-app:$tag). Acmak icin:  .\minikube.ps1 forward" -ForegroundColor Green
        }
        'forward' {
            Test-Tools 'kubectl'
            if ($LocalPort -ne 8080) {
                Write-Host "Uyari: APP_URL http://localhost:8080 olarak ayarli; farkli port kullanirsaniz terraform/variables.tf icindeki APP_URL'yi de guncelleyin." -ForegroundColor Yellow
            }
            Write-Host "CloudPulse -> http://localhost:$LocalPort   (durdurmak icin Ctrl+C)"
            Kube port-forward svc/cloudpulse-web "${LocalPort}:80"
        }
        'status' {
            Test-Tools 'kubectl'
            Kube get 'pods,svc,hpa'
        }
        'logs' {
            Test-Tools 'kubectl'
            Kube logs -l app.kubernetes.io/name=cloudpulse-web --all-containers --prefix --tail=50 -f
        }
        'diagnose' {
            Test-Tools 'kubectl'
            Invoke-Diagnose
        }
        'down' {
            Test-Tools 'terraform'
            $script:Secrets = Initialize-Secrets
            Invoke-Terraform 'destroy'
        }
        'destroy' {
            Test-Tools 'minikube'
            Write-Step "minikube cluster'i siliniyor: $Context"
            Run minikube delete -p $Context
        }
    }
}
catch {
    Write-Host ''
    Write-Host "HATA: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
