// VNet + AKS node subnet + an NSG that Azure Chaos Studio will fault (A1, C1b).
targetScope = 'resourceGroup'

param location string
param namePrefix string
param vnetAddressSpace string = '10.224.0.0/12'
param aksSubnetPrefix string = '10.224.0.0/16'

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-aks-nsg'
  location: location
  // Intentionally no deny rules here — Chaos Studio's "NSG Security Rule" fault
  // injects/removes the deny rule at experiment runtime.
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${namePrefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressSpace ]
    }
    subnets: [
      {
        name: 'aks'
        properties: {
          addressPrefix: aksSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

output nsgId string = nsg.id
output nsgName string = nsg.name
output vnetId string = vnet.id
output aksSubnetId string = '${vnet.id}/subnets/aks'
