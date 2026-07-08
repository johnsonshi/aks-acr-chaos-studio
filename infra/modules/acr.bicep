// Premium, geo-replicated ACR (2-3 replicas recommended, see README C1a capacity note).
// Zone redundancy is on by default in supported regions; dedicated data endpoints enabled.
// Diagnostic logs -> Log Analytics for pull/auth SLIs.
targetScope = 'resourceGroup'

param name string
param location string
@description('Replica regions (exclude home region). 1-2 recommended so total replicas = 2-3. Use AZ-capable regions for zone redundancy.')
param replicaRegions array = [ 'westus3', 'westeurope' ]
param logAnalyticsId string

@description('Enable customer-managed key (CMK) so experiment F1 can fault the key vault.')
param enableCmk bool = false
param cmkUamiId string = ''
param cmkUamiClientId string = ''
param cmkKeyUriWithVersion string = ''

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  sku: {
    name: 'Premium'
  }
  identity: enableCmk ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${cmkUamiId}': {}
    }
  } : {
    type: 'SystemAssigned'
  }
  properties: {
    adminUserEnabled: false
    dataEndpointEnabled: true // dedicated data endpoints (A4)
    zoneRedundancy: 'Enabled'
    publicNetworkAccess: 'Enabled'
    encryption: enableCmk ? {
      status: 'enabled'
      keyVaultProperties: {
        identity: cmkUamiClientId
        keyIdentifier: cmkKeyUriWithVersion
      }
    } : null
  }
}

resource replicas 'Microsoft.ContainerRegistry/registries/replications@2023-07-01' = [for region in replicaRegions: {
  parent: acr
  name: region
  location: region
  properties: {
    zoneRedundancy: 'Enabled'
  }
}]

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'acr-to-la'
  scope: acr
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      { category: 'ContainerRegistryRepositoryEvents', enabled: true }
      { category: 'ContainerRegistryLoginEvents', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

output id string = acr.id
output name string = acr.name
output loginServer string = acr.properties.loginServer
