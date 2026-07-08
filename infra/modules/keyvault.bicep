// Optional CMK dependency for experiment F1 (Key Vault Deny Access / Disable Certificate).
// Uses a user-assigned identity for ACR encryption to avoid the system-identity chicken-and-egg.
targetScope = 'resourceGroup'

param location string
param namePrefix string
param tenantId string = subscription().tenantId

var vaultName = take(toLower(replace('${namePrefix}kv${uniqueString(resourceGroup().id)}', '-', '')), 24)

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-acr-cmk-uami'
  location: location
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true // required for ACR CMK
    enableRbacAuthorization: false
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: uami.properties.principalId
        permissions: {
          keys: [ 'get', 'wrapKey', 'unwrapKey' ]
        }
      }
    ]
  }
}

resource key 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: kv
  name: '${namePrefix}-acr-cmk'
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [ 'wrapKey', 'unwrapKey' ]
  }
}

output vaultId string = kv.id
output vaultName string = kv.name
output vaultUri string = kv.properties.vaultUri
output keyUriWithVersion string = key.properties.keyUriWithVersion
output uamiId string = uami.id
output uamiClientId string = uami.properties.clientId
output uamiPrincipalId string = uami.properties.principalId
