// Infra backbone for the AKS -> ACR/MAR chaos resiliency showcase.
// Deploy: az deployment group create -g <rg> -f infra/main.bicep -p infra/main.bicepparam
// Then deploy infra/chaos.bicep (targets + experiments) with the outputs from this deployment.
targetScope = 'resourceGroup'

@description('Short lowercase prefix for resource names, e.g. "acrchaos".')
param namePrefix string
param location string = resourceGroup().location

@description('ACR replica regions (exclude the home region = location). 1-2 recommended. Use AZ-capable regions.')
param replicaRegions array = [ 'westus3', 'westeurope' ]

@description('Enable a CMK key vault so experiment F1 can fault it.')
param enableCmk bool = false

@description('AKS node-pool availability zones. Empty = portable (deploys anywhere). Set ["1","2","3"] for experiment C2 in a zone-capable region + VM SKU.')
param aksZones array = []

@description('AKS node VM size. Must be offered + have quota in your subscription/region (check: az vm list-skus -l <region> --size <sku>). Default suits most standard subs.')
param aksVmSize string = 'Standard_D2s_v3'

var acrName = take(toLower(replace('${namePrefix}acr${uniqueString(resourceGroup().id)}', '-', '')), 50)

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    namePrefix: namePrefix
  }
}

module la 'modules/loganalytics.bicep' = {
  name: 'loganalytics'
  params: {
    location: location
    name: '${namePrefix}-la'
  }
}

module kv 'modules/keyvault.bicep' = if (enableCmk) {
  name: 'keyvault'
  params: {
    location: location
    namePrefix: namePrefix
  }
}

module acr 'modules/acr.bicep' = {
  name: 'acr'
  params: {
    name: acrName
    location: location
    replicaRegions: replicaRegions
    logAnalyticsId: la.outputs.id
    enableCmk: enableCmk
    cmkUamiId: enableCmk ? kv!.outputs.uamiId : ''
    cmkUamiClientId: enableCmk ? kv!.outputs.uamiClientId : ''
    cmkKeyUriWithVersion: enableCmk ? kv!.outputs.keyUriWithVersion : ''
  }
}

module aks 'modules/aks.bicep' = {
  name: 'aks'
  params: {
    name: '${namePrefix}-aks'
    location: location
    aksSubnetId: network.outputs.aksSubnetId
    logAnalyticsId: la.outputs.id
    zones: aksZones
    vmSize: aksVmSize
  }
}

module acrPull 'modules/acrpull.bicep' = {
  name: 'acrpull'
  params: {
    acrName: acr.outputs.name
    kubeletObjectId: aks.outputs.kubeletObjectId
  }
}

module loadTest 'modules/loadtesting.bicep' = {
  name: 'loadtesting'
  params: {
    name: '${namePrefix}-lt'
    location: location
  }
}

output acrName string = acr.outputs.name
output acrLoginServer string = acr.outputs.loginServer
output acrId string = acr.outputs.id
output aksName string = aks.outputs.name
output aksId string = aks.outputs.id
output aksNodeResourceGroup string = aks.outputs.nodeResourceGroup
output nsgId string = network.outputs.nsgId
output nsgName string = network.outputs.nsgName
output logAnalyticsId string = la.outputs.id
output loadTestId string = loadTest.outputs.id
output keyVaultId string = enableCmk ? kv!.outputs.vaultId : ''
