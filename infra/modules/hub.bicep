targetScope = 'resourceGroup'

param location string
param hubPrefix string
param firewallSubnetPrefix string
param dnsServerIp string
param aiAgentSubnetPrefix string
param aiVmSubnetPrefix string
param aiVnetPrefix string
param region string = location
param vnetName string
param publicIpName string
param firewallPolicyName string
param firewallName string

var vmKmsIps = [
  '20.118.99.224'
  '40.83.235.53'
  '23.102.135.246'
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubPrefix
      ]
    }
    dhcpOptions: {
      dnsServers: [
        dnsServerIp
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: firewallSubnetPrefix
        }
      }
    ]
  }
}

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource policy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: firewallPolicyName
  location: location
  properties: {
    sku: {
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
  }
}

resource rules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: policy
  name: 'rcg-hosted-agent'
  properties: {
    priority: 100
    ruleCollections: [
      {
        name: 'net-allow'
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            name: 'dns-to-private-resolver'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'UDP'
              'TCP'
            ]
            sourceAddresses: [
              aiVnetPrefix
            ]
            destinationAddresses: [
              dnsServerIp
            ]
            destinationPorts: [
              '53'
            ]
          }
          {
            name: 'agent-subnet-entra-id'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              aiAgentSubnetPrefix
            ]
            destinationAddresses: [
              'AzureActiveDirectory'
            ]
            destinationPorts: [
              '443'
            ]
          }
          {
            name: 'vm-subnet-windows-kms'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              aiVmSubnetPrefix
            ]
            destinationAddresses: vmKmsIps
            destinationPorts: [
              '1688'
            ]
          }
        ]
      }
      {
        name: 'app-allow'
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        priority: 200
        action: {
          type: 'Allow'
        }
        rules: [
          {
            name: 'agent-subnet-managed-identity'
            ruleType: 'ApplicationRule'
            sourceAddresses: [
              aiAgentSubnetPrefix
            ]
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: [
              'control-${region}.identity.azure.net'
              '*.identity.azure.net'
              '${region}.login.microsoft.com'
              '*.login.microsoft.com'
              'login.microsoftonline.com'
              '*.login.microsoftonline.com'
            ]
          }
        ]
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: firewallName
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    firewallPolicy: {
      id: policy.id
    }
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/AzureFirewallSubnet'
          }
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
  dependsOn: [
    rules
  ]
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
