#OUTPUT variables
output "network_resource_group" {
  value = azurerm_resource_group.resogroup.name
  description = "Network Resource Group"
}

output "virtual_network" {
  value = azurerm_virtual_network.vnet.name
  description = "Virtual Network"
}

output "masters_subnet" {
  value = azurerm_subnet.masters.id
  description = "Control Plane Subnet"
}

output "workers_subnet" {
  value = azurerm_subnet.workers.id
  description = "Workers Subnet"
}
