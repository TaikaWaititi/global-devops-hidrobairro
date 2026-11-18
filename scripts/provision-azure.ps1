[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]{5,25}$')][string]$Prefix,
    [string]$Location = 'brazilsouth'
)
$ErrorActionPreference = 'Stop'
function Invoke-Azure {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $result = & az @Arguments --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI falhou na operacao $($Arguments[0..1] -join ' ')." }
    return $result
}
foreach ($key in 'ORACLE_PASSWORD','ORACLE_ADMIN_PASSWORD','RABBITMQ_PASSWORD','JWT_SECRET') {
    if (![Environment]::GetEnvironmentVariable($key)) { throw "Variavel obrigatoria ausente: $key" }
}
if ($env:ORACLE_PASSWORD -notmatch '^[A-Za-z][A-Za-z0-9]{15,63}$' -or
    $env:ORACLE_ADMIN_PASSWORD -notmatch '^[A-Za-z][A-Za-z0-9]{15,63}$') {
    throw 'Use senhas Oracle aleatorias alfanumericas de 16 a 64 caracteres, iniciadas por letra.'
}
try { $jwtBytes = [Convert]::FromBase64String($env:JWT_SECRET) } catch { throw 'JWT_SECRET deve ser Base64.' }
if ($jwtBytes.Length -lt 32) { throw 'JWT_SECRET deve representar ao menos 32 bytes aleatorios.' }
if ([bool]$env:BOOTSTRAP_GESTOR_EMAIL -ne [bool]$env:BOOTSTRAP_GESTOR_PASSWORD) {
    throw 'Informe email e senha do gestor juntos, ou deixe ambos ausentes.'
}
if ($env:BOOTSTRAP_GESTOR_PASSWORD -and $env:BOOTSTRAP_GESTOR_PASSWORD.Length -lt 12) {
    throw 'A senha de bootstrap do gestor deve ter pelo menos 12 caracteres.'
}

$rg = "rg-$Prefix"
$vnet = "vnet-$Prefix"
$app = "app-$Prefix"
$plan = "plan-$Prefix"
$container = "data-$Prefix"
Invoke-Azure account set --subscription $SubscriptionId
$exists = Invoke-Azure group exists --name $rg --output tsv
if ($exists -eq 'true') {
    $projectTag = Invoke-Azure group show --name $rg --query tags.project --output tsv
    if ($projectTag -ne 'HidroBairro-Sul') { throw "O grupo $rg nao pertence a este projeto." }
} else {
    Invoke-Azure group create --name $rg --location $Location --tags project=HidroBairro-Sul --output none
}
$existingPlan = Invoke-Azure appservice plan list --resource-group $rg --query "[?name=='$plan'].id" --output tsv
if (!$existingPlan) {
    Invoke-Azure appservice plan create --resource-group $rg --name $plan --is-linux --sku B1 --output none
}
$existingVnet = Invoke-Azure network vnet list --resource-group $rg --query "[?name=='$vnet'].id" --output tsv
if (!$existingVnet) {
    Invoke-Azure network vnet create --resource-group $rg --name $vnet --address-prefixes 10.42.0.0/16 `
        --subnet-name aci --subnet-prefixes 10.42.1.0/24 --output none
}
Invoke-Azure network vnet subnet update --resource-group $rg --vnet-name $vnet --name aci `
    --delegations Microsoft.ContainerInstance/containerGroups --output none
Invoke-Azure network vnet subnet create --resource-group $rg --vnet-name $vnet --name web `
    --address-prefixes 10.42.2.0/24 --delegations Microsoft.Web/serverFarms --output none
Invoke-Azure network public-ip create --resource-group $rg --name "pip-$Prefix" --sku Standard --allocation-method Static --output none
Invoke-Azure network nat gateway create --resource-group $rg --name "nat-$Prefix" --public-ip-addresses "pip-$Prefix" --output none
Invoke-Azure network vnet subnet update --resource-group $rg --vnet-name $vnet --name aci --nat-gateway "nat-$Prefix" --output none
Invoke-Azure network vnet subnet update --resource-group $rg --vnet-name $vnet --name web --nat-gateway "nat-$Prefix" --output none
$subnetId = Invoke-Azure network vnet subnet show --resource-group $rg --vnet-name $vnet --name aci --query id --output tsv

# Oracle e Rabbit ficam na rede privada; nao expor portas de dados na Internet.
# ACI e um banco de piloto: a exclusao/recriacao do grupo de containers perde dados.
# A Release atualiza somente App Service; manter ACI ativo durante a avaliacao.
$spec = @{
    apiVersion = '2021-10-01'
    type = 'Microsoft.ContainerInstance/containerGroups'
    name = $container
    location = $Location
    properties = @{
        osType = 'Linux'
        restartPolicy = 'Always'
        subnetIds = @(@{ id = $subnetId })
        ipAddress = @{ type = 'Private'; ports = @(@{ protocol='TCP'; port=1521 }, @{ protocol='TCP'; port=5672 }) }
        containers = @(
            @{
                name = 'oracle'
                properties = @{
                    image = 'gvenzl/oracle-free:23-slim'
                    ports = @(@{ port=1521 })
                    resources = @{ requests = @{ cpu=2; memoryInGB=4 } }
                    environmentVariables = @(
                        @{ name='ORACLE_PASSWORD'; secureValue=$env:ORACLE_ADMIN_PASSWORD },
                        @{ name='APP_USER'; value='hidrobairro' },
                        @{ name='APP_USER_PASSWORD'; secureValue=$env:ORACLE_PASSWORD }
                    )
                }
            },
            @{
                name = 'rabbitmq'
                properties = @{
                    image = 'rabbitmq:4.1-alpine'
                    ports = @(@{ port=5672 })
                    resources = @{ requests = @{ cpu=1; memoryInGB=1 } }
                    environmentVariables = @(
                        @{ name='RABBITMQ_DEFAULT_USER'; value='hidrobairro' },
                        @{ name='RABBITMQ_DEFAULT_PASS'; secureValue=$env:RABBITMQ_PASSWORD }
                    )
                }
            }
        )
    }
}
$tempConfig = [IO.Path]::GetTempFileName()
try {
    $existingData = Invoke-Azure container list --resource-group $rg --query "[?name=='$container'].id" --output tsv
    if (!$existingData) {
        $spec | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempConfig -Encoding utf8
        Invoke-Azure container create --resource-group $rg --file $tempConfig --output none
    } else { Write-Host 'Container de dados existente preservado; nenhuma recriacao executada.' }
} finally { Remove-Item -LiteralPath $tempConfig -ErrorAction SilentlyContinue }
$privateIp = Invoke-Azure container show --resource-group $rg --name $container --query ipAddress.ip --output tsv
if (!$privateIp) { throw 'ACI nao recebeu endereco privado.' }

$existingApp = Invoke-Azure webapp list --resource-group $rg --query "[?name=='$app'].id" --output tsv
if (!$existingApp) {
    Invoke-Azure webapp create --resource-group $rg --plan $plan --name $app --runtime 'JAVA:21-java21' --output none
}
Invoke-Azure webapp vnet-integration add --resource-group $rg --name $app --vnet $vnet --subnet web --output none
Invoke-Azure webapp update --resource-group $rg --name $app --https-only true --output none
Invoke-Azure webapp config set --resource-group $rg --name $app --always-on true --min-tls-version 1.2 `
    --ftps-state Disabled --startup-file 'java -jar /home/site/wwwroot/app.jar' --output none
Invoke-Azure webapp log config --resource-group $rg --name $app --docker-container-logging filesystem --output none

$settings = @{
    ORACLE_URL = "jdbc:oracle:thin:@//$($privateIp):1521/FREEPDB1"
    ORACLE_USER = 'hidrobairro'
    ORACLE_PASSWORD = $env:ORACLE_PASSWORD
    JWT_SECRET = $env:JWT_SECRET
    SPRING_PROFILES_ACTIVE = 'cloud'
    RABBITMQ_HOST = $privateIp
    RABBITMQ_USER = 'hidrobairro'
    RABBITMQ_PASSWORD = $env:RABBITMQ_PASSWORD
    HIDROBAIRRO_BOOTSTRAP_ENABLED = 'false'
}
if ($env:GEMINI_MODEL) { $settings.GEMINI_MODEL=$env:GEMINI_MODEL }
if ($env:GEMINI_API_KEY) {
    $settings.GEMINI_API_KEY=$env:GEMINI_API_KEY
    $settings.AI_CHAT_MODEL='google-genai'
}
if ($env:BOOTSTRAP_GESTOR_EMAIL) {
    $settings.HIDROBAIRRO_BOOTSTRAP_ENABLED='true'
    $settings.BOOTSTRAP_GESTOR_EMAIL=$env:BOOTSTRAP_GESTOR_EMAIL
    $settings.BOOTSTRAP_GESTOR_PASSWORD=$env:BOOTSTRAP_GESTOR_PASSWORD
}
$tempSettings = [IO.Path]::GetTempFileName()
try {
    $settings | ConvertTo-Json | Set-Content -LiteralPath $tempSettings -Encoding utf8
    Invoke-Azure webapp config appsettings set --resource-group $rg --name $app --settings "@$tempSettings" --output none
} finally { Remove-Item -LiteralPath $tempSettings -ErrorAction SilentlyContinue }
Write-Host "Infra criada. resourceGroup=$rg webAppName=$app. Configure a Service Connection com escopo nesse grupo."
