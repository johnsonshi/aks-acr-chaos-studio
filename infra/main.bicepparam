using './main.bicep'

param namePrefix = 'acrchaos'
param location = 'eastus2'
// Home region = location. Keep total replicas at 2-3 for failover capacity (README C1a). Use AZ-capable regions.
param replicaRegions = [ 'westus3', 'westeurope' ]
// Set true to also stand up a CMK key vault for experiment F1.
param enableCmk = false
