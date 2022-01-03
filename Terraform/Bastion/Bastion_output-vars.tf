#OUTPUT variables for Bastion module
#Bastion VM public IP
data "azurerm_public_ip" "bastion_pub_ip" {
  name                = azurerm_public_ip.bastion_pub_ip.name
  resource_group_name = azurerm_linux_virtual_machine.bastion.resource_group_name
}

output "bastion_public_ip" {
  value = data.azurerm_public_ip.bastion_pub_ip.ip_address
  description = "Public IP assigned to the bastion host"
}
