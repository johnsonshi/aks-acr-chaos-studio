// Azure Load Testing resource used by the "Start/Stop load test" Chaos orchestration action
// to drive real pull storms (D1/D2/D3) against a DEDICATED test registry.
targetScope = 'resourceGroup'

param name string
param location string

resource lt 'Microsoft.LoadTestService/loadTests@2022-12-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

output id string = lt.id
output name string = lt.name
