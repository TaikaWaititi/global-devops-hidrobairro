[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Organization,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$AzureServiceConnection,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$WebAppName
)
$ErrorActionPreference = 'Stop'
function Invoke-Pipelines {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $result = & az @Arguments --organization $Organization --project $Project --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Azure Pipelines CLI falhou: $($Arguments[0..2] -join ' ')." }
    return $result
}
$endpoints = Invoke-Pipelines devops service-endpoint list --output json | ConvertFrom-Json
$endpoint = @($endpoints | Where-Object { $_.name -eq $AzureServiceConnection -and $_.type -eq 'azurerm' })
if ($endpoint.Count -ne 1) { throw 'Crie primeiro uma Service Connection Azure Resource Manager (Workload Identity Federation) com escopo no Resource Group.' }
$groups = Invoke-Pipelines pipelines variable-group list --output json | ConvertFrom-Json
if (@($groups | Where-Object { $_.name -eq 'hidrobairro-deploy' }).Count) {
    throw 'O grupo hidrobairro-deploy ja existe. Configure-o sem sobrescrever valores existentes.'
}
# Grupo contem apenas nomes de recursos e conexao. Senhas ficam nas App Settings/secureValue da infra.
Invoke-Pipelines pipelines variable-group create --name hidrobairro-deploy --authorize true `
    --variables "azureServiceConnection=$AzureServiceConnection" "resourceGroup=$ResourceGroup" "webAppName=$WebAppName" --output none
$repo = Invoke-Pipelines repos show --repository hidrobairro-java --output json | ConvertFrom-Json
Invoke-Pipelines pipelines create --name HidroBairro-CI --repository $repo.id --repository-type tfsgit `
    --branch main --yaml-path azure-pipeline.yml --skip-first-run true --output none
Invoke-Pipelines pipelines create --name HidroBairro-Release --repository $repo.id --repository-type tfsgit `
    --branch main --yaml-path azure-release.yml --skip-first-run true --output none
Write-Host 'Pipelines criadas sem executar build/deploy inicial.'
Write-Host 'Autorize a Service Connection somente para HidroBairro-Release; depois use uma PR vinculada ao Boards para iniciar o fluxo.'
