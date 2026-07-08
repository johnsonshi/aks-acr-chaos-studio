// Grant the AKS kubelet identity pull access on the registry.
// NOTE: For ABAC-enabled registries, AcrPull is IGNORED — assign "Container Registry Repository Reader"
// instead (see README §9). Swap acrPullRoleId for the Repository Reader role definition id in that case.
targetScope = 'resourceGroup'

param acrName string
param kubeletObjectId string

// AcrPull built-in role
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, kubeletObjectId, acrPullRoleId)
  scope: acr
  properties: {
    principalId: kubeletObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalType: 'ServicePrincipal'
  }
}
