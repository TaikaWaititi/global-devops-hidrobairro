[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^https://dev\.azure\.com/[^/]+/?$')][string]$Organization,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$ReviewerEmail,
    [Parameter(Mandatory)][string]$ReviewerRM
)
$ErrorActionPreference = 'Stop'
function Invoke-DevOps {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $result = & az @Arguments --organization $Organization --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Azure DevOps CLI falhou: $($Arguments[0..2] -join ' ')." }
    return $result
}
$existing = Invoke-DevOps devops project list --query "value[?name=='$Project'].id" --output tsv
if ($existing) { throw 'O projeto ja existe; bootstrap recusado para preservar configuracoes existentes.' }
Invoke-DevOps devops project create --name $Project --visibility private --source-control git --process Basic --output none
$repo = Invoke-DevOps repos create --project $Project --name hidrobairro-java --output json | ConvertFrom-Json
# A origem de importacao e exclusivamente o repositorio DevOps autorizado pelo usuario.
Invoke-DevOps repos import create --project $Project --repository $repo.id --git-source-url `
    'https://github.com/TaikaWaititi/global-devops-hidrobairro.git' --output none
$task = Invoke-DevOps boards work-item create --project $Project --type Task `
    --title 'Publicar HidroBairro Sul Java no Azure' --output json | ConvertFrom-Json
Invoke-DevOps repos policy approver-count create --project $Project --repository-id $repo.id --branch main `
    --enabled true --blocking true --minimum-approver-count 1 --creator-vote-counts true `
    --allow-downvotes false --reset-on-source-push true --output none
Invoke-DevOps repos policy work-item-linking create --project $Project --repository-id $repo.id --branch main `
    --enabled true --blocking true --output none
Invoke-DevOps repos policy required-reviewer create --project $Project --repository-id $repo.id --branch main `
    --enabled true --blocking true --required-reviewer-ids $ReviewerEmail --message "Revisao obrigatoria RM $ReviewerRM" --output none
# Sem politica de build pre-merge: o enunciado exige CI apenas apos merge em main.
Write-Host "Projeto privado criado. Repositorio=$($repo.remoteUrl) Tarefa=$($task.id)."
Write-Host 'Revisor deve ter Display Name identificado pelo RM; remover permissoes de bypass da main.'
Write-Host 'Criar pipelines HidroBairro-CI (azure-pipeline.yml) e HidroBairro-Release (azure-release.yml).'
Write-Host 'Autorizar Service Connection e grupo hidrobairro-deploy somente para a Release.'
