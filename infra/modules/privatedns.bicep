// A private DNS zone linked to the hub and spoke VNets.

param zoneName string
param tags object
param vnetIds array

resource zone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (vnetId, i) in vnetIds: {
  parent: zone
  name: 'link-${last(split(vnetId, '/'))}'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}]

output zoneId string = zone.id
output zoneName string = zone.name
