[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Organization,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [string]$ConnectionName = 'sc-hidrobairro-azure',
    [string]$IdentityName = 'id-hbsul-devops-deploy'
)
$ErrorActionPreference = 'Stop'
function Invoke-ConnectionCli {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $result = & az @Arguments --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI falhou: $($Arguments[0..1] -join ' ')." }
    return $result
}
$account = Invoke-ConnectionCli account show --output json | ConvertFrom-Json
$projectInfo = Invoke-ConnectionCli devops project show --organization $Organization --project $Project --output json | ConvertFrom-Json
$identityId = Invoke-ConnectionCli identity list --resource-group $ResourceGroup --query "[?name=='$IdentityName'].id" --output tsv
if (!$identityId) {
    Invoke-ConnectionCli identity create --resource-group $ResourceGroup --name $IdentityName --output none
}
$identity = Invoke-ConnectionCli identity show --resource-group $ResourceGroup --name $IdentityName --output json | ConvertFrom-Json
$scope = "/subscriptions/$($account.id)/resourceGroups/$ResourceGroup"
$roles = Invoke-ConnectionCli role assignment list --scope $scope --output json | ConvertFrom-Json
if (!@($roles | Where-Object { $_.principalId -eq $identity.principalId -and $_.roleDefinitionId -like '*/de139f84-1756-47ae-9be6-808fbbe84772' }).Count) {
    Invoke-ConnectionCli role assignment create --assignee-object-id $identity.principalId --assignee-principal-type ServicePrincipal `
        --role 'Website Contributor' --scope $scope --output none
}
$connections = Invoke-ConnectionCli devops service-endpoint list --organization $Organization --project $Project --output json | ConvertFrom-Json
$connection = @($connections | Where-Object { $_.name -eq $ConnectionName })
if (!$connection.Count) {
    $spec = @{
        name=$ConnectionName; type='azurerm'; url='https://management.azure.com/'; isShared=$false; isReady=$true
        authorization=@{ scheme='WorkloadIdentityFederation'; parameters=@{ tenantid=$identity.tenantId; serviceprincipalid=$identity.clientId } }
        data=@{ subscriptionId=$account.id; subscriptionName=$account.name; environment='AzureCloud'; scopeLevel='Subscription'; creationMode='Manual'; identityType='ManagedIdentity' }
        serviceEndpointProjectReferences=@(@{ projectReference=@{ id=$projectInfo.id; name=$Project }; name=$ConnectionName })
    }
    $tempPath=[IO.Path]::GetTempFileName()
    try {
        $spec | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tempPath -Encoding utf8
        $connection = @(Invoke-ConnectionCli devops service-endpoint create --organization $Organization --project $Project `
            --service-endpoint-configuration $tempPath --output json | ConvertFrom-Json)
    } finally { Remove-Item -LiteralPath $tempPath -ErrorAction SilentlyContinue }
}
if ($connection.Count -ne 1) { throw 'Nome de conexao ambiguo.' }
$detail = Invoke-ConnectionCli devops service-endpoint show --organization $Organization --project $Project --id $connection[0].id --output json | ConvertFrom-Json
if ($detail.authorization.scheme -ne 'WorkloadIdentityFederation' -or
    $detail.authorization.parameters.serviceprincipalid -ne $identity.clientId) {
    throw 'A conexao existente usa outra identidade ou outro metodo de autenticacao; nenhuma sobrescrita executada.'
}
$issuer = $detail.authorization.parameters.workloadIdentityFederationIssuer
$subject = $detail.authorization.parameters.workloadIdentityFederationSubject
if (!$issuer -or !$subject) { throw 'Azure DevOps nao retornou issuer/subject da federacao.' }
Invoke-ConnectionCli identity federated-credential create --resource-group $ResourceGroup --identity-name $IdentityName `
    --name azuredevops-release --issuer $issuer --subject $subject --audiences api://AzureADTokenExchange --output none
Write-Host "Conexao $ConnectionName pronta, com Website Contributor somente no grupo $ResourceGroup."
Write-Host 'Autorize essa conexao apenas para a pipeline de Release nas permissoes de pipeline do recurso.'
