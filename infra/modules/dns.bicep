targetScope = 'resourceGroup'

param location string
param dnsPrefix string
param resolverSubnetPrefix string
param resolverInboundIp string
param firewallPrivateIp string
param vnetName string
param resolverSubnetName string
param routeTableName string
param resolverName string
param zoneLinkName string
var zoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.azurecr.io'
]

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
        dnsPrefix
      ]
    }
    dhcpOptions: {
      dnsServers: [
        resolverInboundIp
      ]
    }
    subnets: [
      {
        name: resolverSubnetName
        properties: {
          addressPrefix: resolverSubnetPrefix
          routeTable: {
            id: routeTable.id
          }
          delegations: [
            {
              name: 'dnsResolver'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
    ]
  }
}

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in zoneNames: {
    name: zone
    location: 'global'
  }
]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zone, i) in zoneNames: {
    parent: zones[i]
    name: zoneLinkName
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
]

resource resolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: resolverName
  location: location
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource inbound 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  parent: resolver
  name: 'inbound'
  location: location
  properties: {
    ipConfigurations: [
      {
        subnet: {
          id: '${vnet.id}/subnets/${resolverSubnetName}'
        }
        privateIpAllocationMethod: 'Static'
        privateIpAddress: resolverInboundIp
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output zoneIds object = {
  cognitiveServices: zones[0].id
  openAi: zones[1].id
  servicesAi: zones[2].id
  acr: zones[3].id
}
