# Infrastructure

Bicep that deploys, at subscription scope into three **existing** resource groups:

- **hub**: hub VNet and Azure Firewall with only the rules the agent needs (DNS, Entra ID, managed identity and login endpoints, Windows activation for the test VM);
- **dns**: DNS VNet, Private DNS Resolver (inbound endpoint) and the private DNS zones, linked to the DNS VNet;
- **ai**: AI VNet (private endpoint, delegated agent, VM and Bastion subnets), Foundry account and project with network injection and the project capability host, ACR with private endpoint, a Windows test VM and a Developer Bastion.

All VNets are peered to the hub, use the Private DNS Resolver as DNS server, and send `0.0.0.0/0` to the firewall.

## Deploy

1. Copy [main.example.bicepparam](main.example.bicepparam) to `main.bicepparam` and replace the placeholders. Address spaces and subnets keep their defaults (`10.0.0.0/16`, `10.1.0.0/16`, `10.2.0.0/16`).
2. Deploy (the subscription is the current Azure CLI one):

```powershell
az account set --subscription <subscription-id>
$env:VM_ADMIN_PASSWORD = '<vm-admin-password>'
az deployment sub create --name <deployment-name> --location <region> --template-file main.bicep --parameters main.bicepparam
```

The deployment takes about 10 to 20 minutes. Its outputs (`projectId`, `projectEndpoint`, `acrLoginServer`, `acrId`, `modelDeploymentName`) are the inputs of the agent deployment, see [DEPLOY-AGENT.md](../DEPLOY-AGENT.md).

## Parameters

| Parameter | Required | Notes |
|---|---|---|
| `hubResourceGroup`, `dnsResourceGroup`, `aiResourceGroup` | yes | Existing resource groups |
| `acrName`, `foundryName`, `projectName` | yes | `acrName` and `foundryName` must be globally unique |
| `vmAdminUsername`, `vmAdminPassword` | yes | Test VM local administrator |
| `location` | no | Default: the deployment region |
| `userObjectId` | no | Entra user granted Foundry User, Foundry Agent Consumer and the ACR push, pull and tasks roles. Skipped when empty |
| `acrAllowedIps` | no | Public IPs allowed on the ACR firewall. When empty, the ACR has **no public access** |
| `modelName`, `modelDeploymentName`, `modelVersion`, `modelCapacity` | no | Model deployment, default `gpt-4.1-mini` |
| `vmSize` | no | Default `Standard_D4as_v7`. Pick a size available in your region |
| names of the other resources (VNets, subnets, firewall, route tables, VM, Bastion, ...) | no | Have generic defaults, see [main.bicep](main.bicep) |

Notes:

- The Foundry account keeps public network access enabled (agent traffic uses the delegated subnet and private endpoints).
- The account capability host is created by the platform when the network injection is set; the Bicep creates the project capability host.
- The Foundry account, the AI VNet and the delegated agent subnet must be in the same region (`location`).
