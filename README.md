# hosted-agent-hub-dns

Test environment for **Microsoft Foundry hosted agents in a custom, hub-and-spoke network**, with a simple agent deployed from a private Azure Container Registry.

```
rg-hub   vnet-hub (10.0.0.0/16)   Azure Firewall (minimal rules)
rg-dns   vnet-dns (10.1.0.0/16)   Private DNS Resolver + private DNS zones
rg-ai    vnet-ai  (10.2.0.0/16)   Foundry (network-injected agent subnet), ACR + private endpoints,
                                  Windows test VM, Developer Bastion
```

All VNets are peered to the hub, use the Private DNS Resolver as DNS server, and send `0.0.0.0/0` to the firewall. Resource group names are parameters.

| Folder | Content |
|---|---|
| [infra](infra) | Bicep for the network, Foundry account and project (with capability hosts), ACR, VM and Bastion. See [infra/README.md](infra/README.md) |
| [agent](agent) | Source and Dockerfile of the sample agent (adapted from the Microsoft Foundry samples) |
| [azd-agent](azd-agent) | Deploy the agent image with `azd` (`deploy.ps1`) |
| [sdk-agent](sdk-agent) | Deploy the agent image with the Azure AI Projects Python SDK |

Both deployment methods work against this infrastructure or any existing Foundry project and ACR: see [DEPLOY-AGENT.md](DEPLOY-AGENT.md).
