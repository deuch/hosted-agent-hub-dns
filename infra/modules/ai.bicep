targetScope = 'resourceGroup'

param location string
param aiPrefix string
param peSubnetPrefix string
param agentSubnetPrefix string
param vmSubnetPrefix string
param bastionSubnetPrefix string
param resolverInboundIp string
param firewallPrivateIp string
param zoneIds object
param acrAllowedIps array
param userObjectId string
param vmSize string
@secure()
param vmAdminPassword string
param vmAdminUsername string
param modelName string
param modelDeploymentName string
param modelVersion string
param modelCapacity int

param vnetName string
param peSubnetName string
param agentSubnetName string
param vmSubnetName string
param routeTableName string
param acrName string
param foundryName string
param projectName string
param vmName string
param nicName string
param bastionName string

var hasUser = !empty(userObjectId)
var acrPublicAccess = empty(acrAllowedIps) ? 'Disabled' : 'Enabled'
var acrIpRules = [
  for ip in acrAllowedIps: {
    action: 'Allow'
    value: ip
  }
]

var roles = {
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  acrPush: '8311e382-0749-4cb8-b61a-304f252e45ec'
  acrTasksContributor: 'fb382eab-e894-4461-af04-94435c366c3f'
  foundryUser: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
  foundryAgentConsumer: 'eed3b665-ab3a-47b6-8f48-c9382fb1dad6'
}

resource routeTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: routeTableName
  location: location
  properties: {
    routes: [
      {
        name: 'default-via-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        aiPrefix
      ]
    }
    dhcpOptions: {
      dnsServers: [
        resolverInboundIp
      ]
    }
    subnets: [
      {
        name: peSubnetName
        properties: {
          addressPrefix: peSubnetPrefix
        }
      }
      {
        name: agentSubnetName
        properties: {
          addressPrefix: agentSubnetPrefix
          routeTable: {
            id: routeTable.id
          }
          delegations: [
            {
              name: 'foundry-agent'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: vmSubnetName
        properties: {
          addressPrefix: vmSubnetPrefix
          routeTable: {
            id: routeTable.id
          }
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ]
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    dataEndpointEnabled: true
    publicNetworkAccess: acrPublicAccess
    networkRuleBypassOptions: 'AzureServices'
    networkRuleSet: empty(acrAllowedIps)
      ? null
      : {
          defaultAction: 'Deny'
          ipRules: acrIpRules
        }
  }
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: '${vnet.id}/subnets/${agentSubnetName}'
        useMicrosoftManagedNetwork: false
      }
    ]
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Default project'
    description: 'Default project for hosted agents'
  }
  dependsOn: [
    model
  ]
}

resource model 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: modelDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

resource acrConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: project
  name: 'acr-private'
  properties: {
    category: 'ContainerRegistry'
    target: acr.properties.loginServer
    authType: 'ManagedIdentity'
    isSharedToAll: true
    credentials: {
      clientId: project.identity.principalId
      resourceId: acr.id
    }
    metadata: {
      ResourceId: acr.id
    }
  }
}

// The platform creates the account capability host implicitly (named <account>@aml_aiagentservice) when networkInjections is set;
// only one is allowed per account, so it is referenced rather than created
resource accountCapHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-06-01' existing = {
  parent: foundry
  name: '${foundryName}@aml_aiagentservice'
}

resource projectCapHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-06-01' = {
  parent: project
  name: 'caphost-${projectName}'
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
  }
  dependsOn: [
    accountCapHost
    acrConnection
  ]
}

module foundryPe 'private-endpoint.bicep' = {
  name: 'pe-foundry'
  params: {
    name: 'pe-${foundryName}'
    location: location
    subnetId: '${vnet.id}/subnets/${peSubnetName}'
    targetResourceId: foundry.id
    groupId: 'account'
    zoneIds: [
      zoneIds.cognitiveServices
      zoneIds.openAi
      zoneIds.servicesAi
    ]
  }
  dependsOn: [
    model
    acrConnection
    projectOnAccount
  ]
}

module acrPe 'private-endpoint.bicep' = {
  name: 'pe-acr'
  params: {
    name: 'pe-${acrName}'
    location: location
    subnetId: '${vnet.id}/subnets/${peSubnetName}'
    targetResourceId: acr.id
    groupId: 'registry'
    zoneIds: [
      zoneIds.acr
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/${vmSubnetName}'
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: vmName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    licenseType: 'Windows_Client'
    osProfile: {
      computerName: take(vmName, 15)
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-24h2-pro'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Developer'
  }
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
  }
  dependsOn: [
    vm
  ]
}

resource projectOnAccount 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, project.id, roles.foundryUser)
  properties: {
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.foundryUser)
  }
}

resource projectAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, project.id, roles.acrPull)
  properties: {
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.acrPull)
  }
}

resource vmFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, vm.id, roles.foundryUser)
  properties: {
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.foundryUser)
  }
}

resource vmAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, vm.id, roles.acrPull)
  properties: {
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.acrPull)
  }
}

resource userFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (hasUser) {
  scope: foundry
  name: guid(foundry.id, userObjectId, roles.foundryUser)
  properties: {
    principalId: userObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.foundryUser)
  }
}

resource userAgentConsumer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (hasUser) {
  scope: foundry
  name: guid(foundry.id, userObjectId, roles.foundryAgentConsumer)
  properties: {
    principalId: userObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.foundryAgentConsumer)
  }
}

resource userAcrRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for role in ['acrPush', 'acrPull', 'acrTasksContributor']: if (hasUser) {
    scope: acr
    name: guid(acr.id, userObjectId, roles[role])
    properties: {
      principalId: userObjectId
      principalType: 'User'
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles[role])
    }
  }
]

output vnetId string = vnet.id
output vnetName string = vnet.name
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output acrId string = acr.id
output foundryName string = foundry.name
output foundryId string = foundry.id
output projectName string = project.name
output projectId string = project.id
output projectEndpoint string = 'https://${foundry.name}.services.ai.azure.com/api/projects/${project.name}'
output modelDeploymentName string = model.name
output vmPrincipalId string = vm.identity.principalId
