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
# Alterar App Settings pode reiniciar o site/SCM. Reenviar o mesmo JAR e idempotente;
# as tentativas abaixo nao executam provisionamento nem alteram o container do banco.
$published = $false
for ($publishAttempt = 1; $publishAttempt -le 4; $publishAttempt++) {
    az webapp deploy --resource-group $ResourceGroup --name $WebApp `
        --src-path $JarPath --type jar --restart true --track-status false --timeout 180000 --output none --only-show-errors
    if ($LASTEXITCODE -eq 0) { $published=$true; break }
    if ($publishAttempt -lt 4) {
        Write-Host "Publicacao nao concluida ($publishAttempt/4). Aguardando estabilizacao do SCM."
        Start-Sleep -Seconds (15 * $publishAttempt)
    }
}
if (!$published) { throw 'Falha no deploy do JAR apos quatro tentativas.' }
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
