// AKS cluster spread across availability zones (for C2), azure CNI on the NSG-guarded subnet,
// Container Insights to Log Analytics. Kubelet identity is used for the AcrPull assignment (see acrpull.bicep).
targetScope = 'resourceGroup'

param name string
param location string
param aksSubnetId string
param logAnalyticsId string
param nodeCount int = 3
param vmSize string = 'Standard_DS3_v2'
param kubernetesVersion string = ''

@description('Node-pool availability zones. Empty = no zone pinning (portable, deploys anywhere). Set to ["1","2","3"] for experiment C2 in a zone-capable region + VM SKU.')
param zones array = []

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: '${name}-dns'
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: nodeCount
        vmSize: vmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: aksSubnetId
        availabilityZones: empty(zones) ? null : zones
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsId
        }
      }
    }
  }
}

output id string = aks.id
output name string = aks.name
output nodeResourceGroup string = aks.properties.nodeResourceGroup
output kubeletObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
