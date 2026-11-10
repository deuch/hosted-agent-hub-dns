targetScope = 'resourceGroup'

param name string
param location string
param subnetId string
param targetResourceId string
param groupId string
param zoneIds array

resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: name
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: [
            groupId
          ]
        }
      }
    ]
  }
}

resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      for (zoneId, i) in zoneIds: {
        name: 'config${i}'
        properties: {
          privateDnsZoneId: zoneId
        }
      }
    ]
  }
}
