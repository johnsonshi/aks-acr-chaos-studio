// Log Analytics workspace: sink for ACR diagnostic logs (ContainerRegistryLoginEvents,
// ContainerRegistryRepositoryEvents) and AKS Container Insights. Queried by observability/*.kql.
targetScope = 'resourceGroup'

param location string
param name string
param retentionInDays int = 30

resource la 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

output id string = la.id
output name string = la.name
output customerId string = la.properties.customerId
