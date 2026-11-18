[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$WebApp,
    [Parameter(Mandatory)][string]$JarPath
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $JarPath -PathType Leaf)) { throw 'JAR nao encontrado.' }
if (!$env:APP_VERSION) { throw 'APP_VERSION deve identificar o commit da CI.' }

# Deploy atualiza somente o JAR. Banco e RabbitMQ nunca sao recriados na Release.
az webapp config appsettings set --resource-group $ResourceGroup --name $WebApp `
    --settings "APP_VERSION=$env:APP_VERSION" --output none --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Falha ao registrar versao do pacote.' }
az webapp deploy --resource-group $ResourceGroup --name $WebApp `
    --src-path $JarPath --type jar --restart true --output none --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Falha no deploy do JAR.' }
$hostName = az webapp show --resource-group $ResourceGroup --name $WebApp --query defaultHostName --output tsv --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel consultar hostname da API.' }
for ($attempt = 1; $attempt -le 36; $attempt++) {
    try {
        $health = Invoke-RestMethod -Uri "https://$hostName/actuator/health" -TimeoutSec 10
        if ($health.status -eq 'UP') { Write-Host "API saudavel em https://$hostName"; exit 0 }
    } catch { Write-Host "Aguardando inicializacao da API ($attempt/36)." }
    Start-Sleep -Seconds 5
}
throw 'Deploy executado, mas API nao ficou saudavel. Consulte logs de inicializacao.'
