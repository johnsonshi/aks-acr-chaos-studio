// Chaos Studio onboarding + experiments for the AKS -> ACR/MAR showcase.
// Deploy AFTER infra/main.bicep, passing the infra outputs.
//   az deployment group create -g <rg> -f infra/chaos.bicep \
//     -p namePrefix=acrchaos nsgName=<nsgName> aksName=<aksName>
//
// Onboards Chaos targets + capabilities on the NSG, AKS (Chaos Mesh), and (optionally) Key Vault,
// then defines experiments and grants each experiment's managed identity the role it needs.
targetScope = 'resourceGroup'

param namePrefix string
param location string = resourceGroup().location
param nsgName string
param aksName string

@description('Chaos Mesh selector namespace where pull-test pods run (workloads/*.yaml).')
param chaosNamespace string = 'chaos-pullers'

@description('CIDR ranges to deny for the A1 "registry unreachable" test. The Chaos NSG fault REJECTS Azure service tags (system tags such as AzureContainerRegistry / MicrosoftContainerRegistry), so resolve your registry IP(s) — e.g. nslookup <registry>.azurecr.io — and set them here, or apply the service tag at an external firewall instead. Default is TEST-NET (RFC 5737) and is inert; replace before running A1.')
param acrDenyCidrs string = '["192.0.2.0/24"]'

@description('ACR login server for the DNS-failure experiment (A2). Chaos Mesh rejects leading *. wildcards, so pass exact FQDNs.')
param acrLoginServer string = ''

@description('Set true and pass keyVaultName to include experiment F1 (Key Vault Deny Access).')
param enableKeyVaultExperiment bool = false
param keyVaultName string = ''

// Built-in role definition ids
var roleNetworkContributor = '4d97b98b-1d4f-4787-a291-c67834d212e7'
var roleAksClusterAdmin = '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8'
var roleKeyVaultContributor = 'f25e0fa2-a7c8-4377-a976-54943a77a395'

// Chaos Mesh DNS patterns must be exact FQDNs or supported globs — a leading "*." is rejected.
var a2DnsPatterns = empty(acrLoginServer) ? '["mcr.microsoft.com"]' : '["mcr.microsoft.com","${acrLoginServer}"]'

// A4: fault ONLY the dedicated data-endpoint FQDN (<registry>.<region>.data.azurecr.io). The login
// endpoint keeps resolving, so auth + manifest succeed and the failure isolates to blob/layer download.
var acrDataEndpoint = empty(acrLoginServer) ? '' : '${split(acrLoginServer, '.')[0]}.${location}.data.azurecr.io'
var a4DnsPatterns = empty(acrDataEndpoint) ? '["invalid.data.azurecr.io"]' : '["${acrDataEndpoint}"]'

// ---------- Existing target resources ----------
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' existing = {
  name: nsgName
}
resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' existing = {
  name: aksName
}
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (enableKeyVaultExperiment) {
  name: keyVaultName
}

// ---------- Chaos targets + capabilities ----------
resource nsgTarget 'Microsoft.Chaos/targets@2024-01-01' = {
  name: 'Microsoft-NetworkSecurityGroup'
  scope: nsg
  properties: {}
}
resource nsgCap 'Microsoft.Chaos/targets/capabilities@2024-01-01' = {
  parent: nsgTarget
  name: 'SecurityRule-1.0'
}

resource aksTarget 'Microsoft.Chaos/targets@2024-01-01' = {
  name: 'Microsoft-AzureKubernetesServiceChaosMesh'
  scope: aks
  properties: {}
}
resource aksNetCap 'Microsoft.Chaos/targets/capabilities@2024-01-01' = {
  parent: aksTarget
  name: 'NetworkChaos-2.2'
}
resource aksDnsCap 'Microsoft.Chaos/targets/capabilities@2024-01-01' = {
  parent: aksTarget
  name: 'DNSChaos-2.2'
}

resource kvTarget 'Microsoft.Chaos/targets@2024-01-01' = if (enableKeyVaultExperiment) {
  name: 'Microsoft-KeyVault'
  scope: kv
  properties: {}
}
resource kvCap 'Microsoft.Chaos/targets/capabilities@2024-01-01' = if (enableKeyVaultExperiment) {
  parent: kvTarget
  name: 'DenyAccess-1.0'
}

// ---------- A1: Full ACR unreachable (NSG deny to resolved registry CIDRs) ----------
resource expA1 'Microsoft.Chaos/experiments@2024-01-01' = {
  name: '${namePrefix}-a1-nsg-block-acr'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    selectors: [
      {
        type: 'List'
        id: 'sel-nsg'
        targets: [ { type: 'ChaosTarget', id: nsgTarget.id } ]
      }
    ]
    steps: [
      {
        name: 'Block ACR egress'
        branches: [
          {
            name: 'branch1'
            actions: [
              {
                type: 'continuous'
                name: 'urn:csci:microsoft:networkSecurityGroup:securityRule/1.0'
                selectorId: 'sel-nsg'
                duration: 'PT10M'
                parameters: [
                  { key: 'name', value: 'ChaosDenyACR' }
                  { key: 'protocol', value: 'TCP' }
                  { key: 'sourceAddresses', value: '["0.0.0.0/0"]' }
                  { key: 'destinationAddresses', value: acrDenyCidrs }
                  { key: 'action', value: 'Deny' }
                  { key: 'destinationPortRanges', value: '["443"]' }
                  { key: 'sourcePortRanges', value: '["0-65535"]' }
                  { key: 'priority', value: '100' }
                  { key: 'direction', value: 'Outbound' }
                ]
              }
            ]
          }
        ]
      }
    ]
  }
  dependsOn: [ nsgCap ]
}

resource raA1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(nsg.id, expA1.id, roleNetworkContributor)
  scope: nsg
  properties: {
    principalId: expA1.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleNetworkContributor)
    principalType: 'ServicePrincipal'
  }
}

// ---------- A2: Registry DNS failure (AKS Chaos Mesh DNS Chaos) ----------
resource expA2 'Microsoft.Chaos/experiments@2024-01-01' = {
  name: '${namePrefix}-a2-dns-failure'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    selectors: [
      {
        type: 'List'
        id: 'sel-aks'
        targets: [ { type: 'ChaosTarget', id: aksTarget.id } ]
      }
    ]
    steps: [
      {
        name: 'DNS failure for registry FQDNs'
        branches: [
          {
            name: 'branch1'
            actions: [
              {
                type: 'continuous'
                name: 'urn:csci:microsoft:azureKubernetesServiceChaosMesh:dnsChaos/2.2'
                selectorId: 'sel-aks'
                duration: 'PT5M'
                parameters: [
                  {
                    key: 'jsonSpec'
                    value: '{"action":"error","mode":"all","patterns":${a2DnsPatterns},"selector":{"namespaces":["${chaosNamespace}"],"labelSelectors":{"role":"chaos-target"}}}'
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  }
  dependsOn: [ aksDnsCap ]
}

resource raA2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, expA2.id, roleAksClusterAdmin)
  scope: aks
  properties: {
    principalId: expA2.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAksClusterAdmin)
    principalType: 'ServicePrincipal'
  }
}

// ---------- A4: Data-endpoint-only DNS failure (AKS Chaos Mesh DNS Chaos on the data endpoint FQDN) ----------
resource expA4 'Microsoft.Chaos/experiments@2024-01-01' = {
  name: '${namePrefix}-a4-data-endpoint-dns'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    selectors: [
      {
        type: 'List'
        id: 'sel-aks'
        targets: [ { type: 'ChaosTarget', id: aksTarget.id } ]
      }
    ]
    steps: [
      {
        name: 'DNS failure for the ACR data endpoint only'
        branches: [
          {
            name: 'branch1'
            actions: [
              {
                type: 'continuous'
                name: 'urn:csci:microsoft:azureKubernetesServiceChaosMesh:dnsChaos/2.2'
                selectorId: 'sel-aks'
                duration: 'PT5M'
                parameters: [
                  {
                    key: 'jsonSpec'
                    value: '{"action":"error","mode":"all","patterns":${a4DnsPatterns},"selector":{"namespaces":["${chaosNamespace}"],"labelSelectors":{"role":"chaos-target"}}}'
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  }
  dependsOn: [ aksDnsCap ]
}

resource raA4 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, expA4.id, roleAksClusterAdmin)
  scope: aks
  properties: {
    principalId: expA4.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAksClusterAdmin)
    principalType: 'ServicePrincipal'
  }
}

// ---------- A3: Latency/packet loss to registry (AKS Chaos Mesh Network Chaos) ----------
resource expA3 'Microsoft.Chaos/experiments@2024-01-01' = {
  name: '${namePrefix}-a3-registry-latency-loss'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    selectors: [
      {
        type: 'List'
        id: 'sel-aks'
        targets: [ { type: 'ChaosTarget', id: aksTarget.id } ]
      }
    ]
    steps: [
      {
        name: 'Packet loss to MCR'
        branches: [
          {
            name: 'branch1'
            actions: [
              {
                type: 'continuous'
                name: 'urn:csci:microsoft:azureKubernetesServiceChaosMesh:networkChaos/2.2'
                selectorId: 'sel-aks'
                duration: 'PT5M'
                parameters: [
                  {
                    key: 'jsonSpec'
                    value: '{"action":"delay","mode":"all","direction":"to","externalTargets":["mcr.microsoft.com"],"delay":{"latency":"300ms","correlation":"50","jitter":"50ms"},"selector":{"namespaces":["${chaosNamespace}"],"labelSelectors":{"role":"chaos-target"}}}'
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  }
  dependsOn: [ aksNetCap ]
}

resource raA3 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, expA3.id, roleAksClusterAdmin)
  scope: aks
  properties: {
    principalId: expA3.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAksClusterAdmin)
    principalType: 'ServicePrincipal'
  }
}

// ---------- F1: CMK key-vault outage (Key Vault Deny Access) ----------
resource expF1 'Microsoft.Chaos/experiments@2024-01-01' = if (enableKeyVaultExperiment) {
  name: '${namePrefix}-f1-keyvault-denyaccess'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    selectors: [
      {
        type: 'List'
        id: 'sel-kv'
        targets: [ { type: 'ChaosTarget', id: kvTarget.id } ]
      }
    ]
    steps: [
      {
        name: 'Deny access to CMK vault'
        branches: [
          {
            name: 'branch1'
            actions: [
              {
                type: 'continuous'
                name: 'urn:csci:microsoft:keyVault:denyAccess/1.0'
                selectorId: 'sel-kv'
                duration: 'PT10M'
                parameters: []
              }
            ]
          }
        ]
      }
    ]
  }
  dependsOn: [ kvCap ]
}

resource raF1 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableKeyVaultExperiment) {
  name: guid(resourceGroup().id, '${namePrefix}-f1', roleKeyVaultContributor)
  scope: kv
  properties: {
    principalId: expF1!.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleKeyVaultContributor)
    principalType: 'ServicePrincipal'
  }
}

output experimentNames array = union(
  [
    expA1.name
    expA2.name
    expA3.name
  ],
  enableKeyVaultExperiment ? [ expF1!.name ] : []
)
