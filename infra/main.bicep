targetScope = 'subscription'

@description('Region of all resources. Defaults to the region of the subscription-level deployment.')
param location string = deployment().location

@description('Existing resource group for the hub VNet and Azure Firewall.')
param hubResourceGroup string
@description('Existing resource group for the DNS VNet, Private DNS Resolver and Private DNS zones.')
param dnsResourceGroup string
@description('Existing resource group for the AI VNet, Foundry, ACR, VM and Bastion.')
param aiResourceGroup string

@description('Object ID of a user to grant Foundry and ACR roles to. Leave empty to skip these assignments.')
param userObjectId string = ''
@description('Public IPs allowed on the ACR firewall (for example for ACR build tasks). Leave empty for an ACR without public access.')
param acrAllowedIps array = []

param vmSize string = 'Standard_D4as_v7'
param vmAdminUsername string
@secure()
param vmAdminPassword string
param modelName string = 'gpt-4.1-mini'
param modelDeploymentName string = modelName
param modelVersion string = '2025-04-14'
param modelCapacity int = 30

@description('Globally unique ACR name.')
param acrName string
@description('Globally unique Foundry account name, also used as custom subdomain.')
param foundryName string
param projectName string

param hubVnetName string = 'vnet-hub'
param firewallName string = 'afw-hub'
param firewallPolicyName string = 'afwp-hub'
param firewallPublicIpName string = 'pip-fw-hub'
param dnsVnetName string = 'vnet-dns'
param dnsResolverSubnetName string = 'snet-dns-inbound'
param dnsRouteTableName string = 'rt-dns'
param dnsResolverName string = 'dnspr-hub'
param dnsZoneLinkName string = 'link-vnet-dns'
param aiVnetName string = 'vnet-ai'
param aiPeSubnetName string = 'snet-pe'
param aiAgentSubnetName string = 'snet-agent'
param aiVmSubnetName string = 'snet-vm'
param aiRouteTableName string = 'rt-ai'
param vmName string = 'vm-test'
param vmNicName string = 'nic-vm-test'
param bastionName string = 'bas-ai'

var hubPrefix = '10.0.0.0/16'
var dnsPrefix = '10.1.0.0/16'
var aiPrefix = '10.2.0.0/16'
var firewallSubnetPrefix = '10.0.0.0/26'
var resolverSubnetPrefix = '10.1.0.0/28'
var resolverInboundIp = '10.1.0.4'
var peSubnetPrefix = '10.2.0.0/28'
var agentSubnetPrefix = '10.2.1.0/24'
var vmSubnetPrefix = '10.2.2.0/28'
var bastionSubnetPrefix = '10.2.3.0/26'

resource hubRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: hubResourceGroup
}

resource dnsRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: dnsResourceGroup
}

resource aiRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: aiResourceGroup
}

module hub 'modules/hub.bicep' = {
  name: 'hub'
  scope: hubRg
  params: {
    location: location
    hubPrefix: hubPrefix
    firewallSubnetPrefix: firewallSubnetPrefix
    dnsServerIp: resolverInboundIp
    aiVnetPrefix: aiPrefix
    aiAgentSubnetPrefix: agentSubnetPrefix
    aiVmSubnetPrefix: vmSubnetPrefix
    vnetName: hubVnetName
    publicIpName: firewallPublicIpName
    firewallPolicyName: firewallPolicyName
    firewallName: firewallName
  }
}

module dns 'modules/dns.bicep' = {
  name: 'dns'
  scope: dnsRg
  params: {
    location: location
    dnsPrefix: dnsPrefix
    resolverSubnetPrefix: resolverSubnetPrefix
    resolverInboundIp: resolverInboundIp
    firewallPrivateIp: hub.outputs.firewallPrivateIp
    vnetName: dnsVnetName
    resolverSubnetName: dnsResolverSubnetName
    routeTableName: dnsRouteTableName
    resolverName: dnsResolverName
    zoneLinkName: dnsZoneLinkName
  }
}

module ai 'modules/ai.bicep' = {
  name: 'ai'
  scope: aiRg
  params: {
    location: location
    aiPrefix: aiPrefix
    peSubnetPrefix: peSubnetPrefix
    agentSubnetPrefix: agentSubnetPrefix
    vmSubnetPrefix: vmSubnetPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    resolverInboundIp: resolverInboundIp
    firewallPrivateIp: hub.outputs.firewallPrivateIp
    zoneIds: dns.outputs.zoneIds
    acrAllowedIps: acrAllowedIps
    userObjectId: userObjectId
    vmSize: vmSize
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
    modelName: modelName
    modelDeploymentName: modelDeploymentName
    modelVersion: modelVersion
    modelCapacity: modelCapacity
    vnetName: aiVnetName
    peSubnetName: aiPeSubnetName
    agentSubnetName: aiAgentSubnetName
    vmSubnetName: aiVmSubnetName
    routeTableName: aiRouteTableName
    acrName: acrName
    foundryName: foundryName
    projectName: projectName
    vmName: vmName
    nicName: vmNicName
    bastionName: bastionName
  }
}

module hubToDns 'modules/peering.bicep' = {
  name: 'peer-hub-to-dns'
  scope: hubRg
  params: {
    vnetName: hub.outputs.vnetName
    remoteVnetId: dns.outputs.vnetId
    peeringName: 'hub-to-dns'
  }
}

module dnsToHub 'modules/peering.bicep' = {
  name: 'peer-dns-to-hub'
  scope: dnsRg
  params: {
    vnetName: dns.outputs.vnetName
    remoteVnetId: hub.outputs.vnetId
    peeringName: 'dns-to-hub'
  }
}

module hubToAi 'modules/peering.bicep' = {
  name: 'peer-hub-to-ai'
  scope: hubRg
  params: {
    vnetName: hub.outputs.vnetName
    remoteVnetId: ai.outputs.vnetId
    peeringName: 'hub-to-ai'
  }
}

module aiToHub 'modules/peering.bicep' = {
  name: 'peer-ai-to-hub'
  scope: aiRg
  params: {
    vnetName: ai.outputs.vnetName
    remoteVnetId: hub.outputs.vnetId
    peeringName: 'ai-to-hub'
  }
}

output acrName string = ai.outputs.acrName
output acrLoginServer string = ai.outputs.acrLoginServer
output acrId string = ai.outputs.acrId
output foundryName string = ai.outputs.foundryName
output projectName string = ai.outputs.projectName
output projectId string = ai.outputs.projectId
output projectEndpoint string = ai.outputs.projectEndpoint
output modelDeploymentName string = ai.outputs.modelDeploymentName
output firewallPrivateIp string = hub.outputs.firewallPrivateIp
