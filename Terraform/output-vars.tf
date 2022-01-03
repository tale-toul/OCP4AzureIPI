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

#The bastion module is a list of 1 element, so the index [0] is required
output "bastion_public_ip" {
  value = module.bastion[0].bastion_public_ip
  description = "Public IP address assigned to the bastion host"
}

output "region_name" {
  value = var.region_name
  description = "Azure region to create resources in"
}
