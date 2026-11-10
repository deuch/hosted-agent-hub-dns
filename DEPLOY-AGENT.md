# Deploying the hosted agent

The agent runs from a **prebuilt image stored in a private Azure Container Registry (ACR)**. You can deploy it in two ways, against infrastructure created by [infra](infra) or against **any existing** Foundry project and ACR.

| | `azd deploy` | Python SDK |
|---|---|---|
| Folder | [azd-agent](azd-agent) | [sdk-agent](sdk-agent) |
| Entry point | `deploy.ps1` (renders the azd files, sets the azd environment, runs `azd deploy`) | `deploy_agent.py` |
| Needs | `azd` with the `azure.ai.agents` extension, Azure CLI | Python 3.10+, `azure-ai-projects` |
| Good for | Local dev loop, `azd ai agent invoke/show` | CI/CD, scripting |

Both methods create a **new version** of the agent each time they run.

## Variables

Both methods use the same inputs. Each one is a parameter or an environment variable.

| Variable | Used by | Description |
|---|---|---|
| `FOUNDRY_PROJECT_ENDPOINT` | SDK | `https://<account>.services.ai.azure.com/api/projects/<project>` |
| `FOUNDRY_PROJECT_RESOURCE_ID` | azd | `/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>` |
| `AGENT_IMAGE` | both | `<acr-name>.azurecr.io/<repository>:<tag>` (or `@sha256:<digest>`) |
| `AGENT_NAME` | both | Agent name. An existing name creates a new version of that agent |
| `MODEL_DEPLOYMENT_NAME` | both | Name of the model deployment in the Foundry account |

Set them once in your shell (PowerShell):

```powershell
$env:FOUNDRY_PROJECT_RESOURCE_ID = '<project-resource-id>'
$env:FOUNDRY_PROJECT_ENDPOINT    = '<project-endpoint>'
$env:AGENT_IMAGE                 = '<acr-name>.azurecr.io/<repository>:<tag>'
$env:AGENT_NAME                  = '<agent-name>'
$env:MODEL_DEPLOYMENT_NAME       = '<model-deployment-name>'
```

If you deployed [infra](infra), the Bicep outputs `projectId`, `projectEndpoint`, `acrLoginServer`, `acrId` and `modelDeploymentName` give you these values (`az deployment sub show -n <deployment-name> --query properties.outputs`).

## Prerequisites

1. Sign in: `az login` and `az account set --subscription <subscription-id>`.
2. A Foundry project that was **created with network injection** on a subnet delegated to `Microsoft.App/environments` (a hosted-agent requirement), with a model deployment.
3. An ACR containing the image, with a private endpoint and `privatelink.azurecr.io` resolving to it from the agent subnet.
4. Roles:
   - the **project managed identity**: **AcrPull** on the ACR (and **Foundry User** on the account);
   - **you** (or the CI principal): **Foundry User** on the project or account;
   - **you**, to build and push images: **AcrPush** and **Container Registry Tasks Contributor** on the ACR.
5. Egress from the agent subnet allows Microsoft Entra ID and the managed identity endpoints (the `AzureActiveDirectory` tag plus `*.identity.azure.net`, `<region>.login.microsoft.com`, `*.login.microsoft.com`, `login.microsoftonline.com`).

### Using an existing project and ACR

Find the values you need:

```powershell
$rg = '<foundry-resource-group>'; $acrRg = '<acr-resource-group>'

az cognitiveservices account list -g $rg --query "[?kind=='AIServices'].{name:name,location:location}" -o table
$accountId = az cognitiveservices account show -g $rg -n <account> --query id -o tsv
az rest --method get --url "https://management.azure.com$accountId/projects?api-version=2025-06-01" --query "value[].id" -o tsv
az cognitiveservices account deployment list -g $rg -n <account> --query "[].name" -o tsv      # model deployments
az acr list -g $acrRg --query "[].{name:name,loginServer:loginServer,id:id}" -o table
```

Check the prerequisites:

```powershell
# Network injection (agent subnet)
az cognitiveservices account show -g $rg -n <account> --query "properties.networkInjections" -o json
# Capability hosts: the account host and a project host must exist and be Succeeded
az rest --method get --url "https://management.azure.com$accountId/capabilityHosts?api-version=2025-06-01" --query "value[].{n:name,s:properties.provisioningState}" -o table
az rest --method get --url "https://management.azure.com$accountId/projects/<project>/capabilityHosts?api-version=2025-06-01" --query "value[].{n:name,s:properties.provisioningState}" -o table
# Project identity pull access on the ACR
$acrId = az acr show -n <acr-name> --query id -o tsv
az role assignment list --scope $acrId --query "[].{role:roleDefinitionName,principal:principalId}" -o table
```

Grant the missing pull access to the project identity if needed:

```powershell
$principalId = az rest --method get --url "https://management.azure.com$accountId/projects/<project>?api-version=2025-06-01" --query identity.principalId -o tsv
az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role AcrPull --scope $acrId
```

## Step 0: build the image (only when the agent code changes)

```powershell
cd agent
az acr build -r <acr-name> -t <repository>:<tag> --platform linux/amd64 .
```

If the ACR has public access disabled, or restricts it to specific IPs, ACR build tasks fail with `client with IP '<ip>' is not allowed access`: they run on Microsoft-owned agents with changing IPs. Options:

- build from a machine inside the network, push with `docker`, or use a dedicated ACR task agent pool;
- or temporarily allow the IP range shown in the error, build, then remove the rule:

```powershell
az acr update -n <acr-name> --public-network-enabled true      # only if public access is disabled
az acr network-rule add -n <acr-name> --ip-address <ip-range-from-the-error>
Start-Sleep 45                                                  # rule propagation
az acr build -r <acr-name> -t <repository>:<tag> --platform linux/amd64 .
az acr network-rule remove -n <acr-name> --ip-address <ip-range-from-the-error>
```

Use a new tag for each change and pass it as `AGENT_IMAGE`. Pin `@sha256:<digest>` for reproducible deployments.

## Method 1: `azd deploy`

[azd-agent/deploy.ps1](azd-agent/deploy.ps1) wraps `azd`. It:

1. renders `azure.yaml` and `src/agent/agent.yaml` from the `.template` files (the agent name must be a literal in these files);
2. creates (or reuses) an azd environment and sets the variables above in it;
3. runs `azd deploy`.

```powershell
cd azd-agent
./deploy.ps1                       # reads the environment variables above
```

or with parameters:

```powershell
./deploy.ps1 `
  -ProjectResourceId '<project-resource-id>' `
  -Image '<acr-name>.azurecr.io/<repository>:<tag>' `
  -AgentName '<agent-name>' `
  -ModelDeployment '<model-deployment-name>'
```

Optional parameters: `-EnvironmentName` (default `<AgentName>-env`), `-ProjectEndpoint` (default derived from the project resource ID) and `-Location` (default read from the Foundry account).

The agent is deployed as the azd service `agent`. Test and inspect it from the `azd-agent` folder:

```powershell
azd ai agent invoke agent "Say hello in one short sentence." --no-prompt
azd ai agent show agent
```

To deploy a new image, run `./deploy.ps1` again with the new `-Image`.

## Method 2: Python SDK

[sdk-agent/deploy_agent.py](sdk-agent/deploy_agent.py) calls `AIProjectClient.agents.create_version` with a `HostedAgentDefinition`, waits until the version is `active`, and can send a test prompt.

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r sdk-agent\requirements.txt

python sdk-agent\deploy_agent.py                         # reads the environment variables above
python sdk-agent\deploy_agent.py --invoke "Say hello in one short sentence."
```

or with options:

```powershell
python sdk-agent\deploy_agent.py `
  --project-endpoint '<project-endpoint>' `
  --image '<acr-name>.azurecr.io/<repository>:<tag>' `
  --agent-name '<agent-name>' `
  --model-deployment '<model-deployment-name>'
```

| Option | Env variable | Required | Notes |
|---|---|---|---|
| `--project-endpoint` | `FOUNDRY_PROJECT_ENDPOINT` | yes | |
| `--image` | `AGENT_IMAGE` | yes | Tag or `@sha256` digest |
| `--agent-name` | `AGENT_NAME` | yes | |
| `--model-deployment` | `MODEL_DEPLOYMENT_NAME` | yes | Passed to the agent as `AZURE_AI_MODEL_DEPLOYMENT_NAME` |
| `--env KEY=VALUE` | | no | Extra container environment variable, repeatable |
| `--cpu`, `--memory` | `AGENT_CPU`, `AGENT_MEMORY` | no | Default `0.5` and `1Gi` |
| `--registry-connection` | `AGENT_REGISTRY_CONNECTION` | no | Not needed in general (see Troubleshooting) |
| `--timeout` | | no | Seconds to wait for `active`, default 600 |
| `--invoke PROMPT` | | no | Sends a prompt through the Responses protocol |

Authentication uses `DefaultAzureCredential` (Azure CLI login, azd login, environment variables, or a managed identity). In CI, the principal only needs **Foundry User** on the project or account.

## Verify

```powershell
python -c "
import os
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
c = AIProjectClient(endpoint=os.environ['FOUNDRY_PROJECT_ENDPOINT'], credential=DefaultAzureCredential())
for v in c.agents.list_versions(agent_name=os.environ['AGENT_NAME']): print(v.version, v.status)
"
```

## Troubleshooting

- **`not_a_registry_connection`**: the project's ACR connection is rejected as a registry connection by the agent service. Do not pass `--registry-connection` or `registryConnectionId`. Without it, the platform pulls with the project identity, which needs **AcrPull** on the ACR.
- **Image not found or pull errors**: check that the project identity has **AcrPull**, the image tag exists, and `privatelink.azurecr.io` resolves to the ACR private endpoint from the agent subnet (the registry login server and the `<region>.data.azurecr.io` data endpoint).
- **Agent stays in `creating` or fails**: check the Azure Firewall rules for the agent subnet (Entra ID and managed identity endpoints) and that the account and project capability hosts are `Succeeded`.
- **`ACR build` rejected with `client with IP ... is not allowed access`**: see Step 0.
- **`azd` validation error `template.name not in valid format`**: the agent name must be a literal in `azure.yaml` and `agent.yaml`. Use `deploy.ps1` instead of editing the templates by hand.
- **Intermittent `CredentialUnavailableError` (SDK) or `AzureDeveloperCLICredential: exit status 1` (azd)**: token retrieval timed out. Run `az login` (and `azd auth login`) again and retry.
- **First call after a deployment is slow**: cold start of a few seconds.
