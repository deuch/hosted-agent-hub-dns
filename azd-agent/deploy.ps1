<#
.SYNOPSIS
Deploys a hosted agent from a prebuilt container image to an existing Foundry project with azd.

.DESCRIPTION
Renders azure.yaml and src/agent/agent.yaml from their templates, creates or updates an azd
environment from the parameters, then runs `azd deploy`. Nothing is hardcoded: every value is a
parameter or an environment variable of the same name.

.PARAMETER ProjectResourceId
ARM resource ID of the Foundry project:
/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>
Env: FOUNDRY_PROJECT_RESOURCE_ID

.PARAMETER Image
Prebuilt image, <registry>.azurecr.io/<repo>:<tag> or @sha256:<digest>. Env: AGENT_IMAGE

.PARAMETER AgentName
Agent name. An existing name creates a new version. Env: AGENT_NAME

.PARAMETER ModelDeployment
Name of the model deployment in the Foundry account. Env: MODEL_DEPLOYMENT_NAME

.PARAMETER EnvironmentName
Optional azd environment name. Default: <AgentName>-env.

.PARAMETER ProjectEndpoint
Optional project endpoint. Default: derived from the project resource ID.

.PARAMETER Location
Optional region of the project. Default: read from the Foundry account with Azure CLI.
#>
[CmdletBinding()]
param(
    [string]$ProjectResourceId = $env:FOUNDRY_PROJECT_RESOURCE_ID,
    [string]$Image = $env:AGENT_IMAGE,
    [string]$AgentName = $env:AGENT_NAME,
    [string]$ModelDeployment = $env:MODEL_DEPLOYMENT_NAME,
    [string]$EnvironmentName,
    [string]$ProjectEndpoint,
    [string]$Location
)

$ErrorActionPreference = 'Stop'

$missing = @()
if (-not $ProjectResourceId) { $missing += '-ProjectResourceId' }
if (-not $Image) { $missing += '-Image' }
if (-not $AgentName) { $missing += '-AgentName' }
if (-not $ModelDeployment) { $missing += '-ModelDeployment' }
if ($missing) { throw "Missing required value(s): $($missing -join ', ')" }

$pattern = '^/subscriptions/(?<sub>[^/]+)/resourceGroups/(?<rg>[^/]+)/providers/Microsoft\.CognitiveServices/accounts/(?<account>[^/]+)/projects/(?<project>[^/]+)$'
$m = [regex]::Match($ProjectResourceId, $pattern, 'IgnoreCase')
if (-not $m.Success) { throw "ProjectResourceId is not a Foundry project resource ID: $ProjectResourceId" }
$subscriptionId = $m.Groups['sub'].Value
$resourceGroup = $m.Groups['rg'].Value
$account = $m.Groups['account'].Value
$project = $m.Groups['project'].Value

if (-not $ProjectEndpoint) { $ProjectEndpoint = "https://$account.services.ai.azure.com/api/projects/$project" }
if (-not $Location) {
    $Location = az cognitiveservices account show --subscription $subscriptionId -g $resourceGroup -n $account --query location -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $Location) { throw 'Unable to read the account location. Pass -Location.' }
}
if (-not $EnvironmentName) { $EnvironmentName = "$AgentName-env" }

Push-Location $PSScriptRoot
try {
    $renderedAzureYaml = (Get-Content azure.yaml.template -Raw).Replace('__AGENT_NAME__', $AgentName)
    Set-Content azure.yaml $renderedAzureYaml -Encoding utf8NoBOM
    $renderedAgentYaml = (Get-Content src/agent/agent.yaml.template -Raw).Replace('__AGENT_NAME__', $AgentName).Replace('__AGENT_IMAGE__', $Image)
    Set-Content src/agent/agent.yaml $renderedAgentYaml -Encoding utf8NoBOM

    $existing = azd env list --output json | ConvertFrom-Json | Where-Object Name -eq $EnvironmentName
    if (-not $existing) {
        azd env new $EnvironmentName --subscription $subscriptionId --location $Location --no-prompt
        if ($LASTEXITCODE -ne 0) { throw 'azd env new failed.' }
    }

    $values = [ordered]@{
        AZURE_SUBSCRIPTION_ID = $subscriptionId
        AZURE_RESOURCE_GROUP = $resourceGroup
        AZURE_LOCATION = $Location
        AZURE_AI_ACCOUNT_NAME = $account
        AZURE_AI_PROJECT_NAME = $project
        AZURE_AI_PROJECT_ID = $ProjectResourceId
        USE_EXISTING_AI_PROJECT = 'true'
        FOUNDRY_PROJECT_ENDPOINT = $ProjectEndpoint
        AGENT_IMAGE = $Image
        MODEL_DEPLOYMENT_NAME = $ModelDeployment
    }
    foreach ($key in $values.Keys) {
        azd env set $key $values[$key] --environment $EnvironmentName
        if ($LASTEXITCODE -ne 0) { throw "azd env set $key failed." }
    }

    azd deploy --environment $EnvironmentName --no-prompt
    if ($LASTEXITCODE -ne 0) { throw 'azd deploy failed.' }
}
finally {
    Pop-Location
}
