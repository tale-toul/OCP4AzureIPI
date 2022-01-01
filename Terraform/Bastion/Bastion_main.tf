#Bastion resources

# Subnet 
resource "azurerm_subnet" "bastion" {
  name = "bastion-${var.suffix}"
  resource_group_name = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes = ["10.0.22.0/24"]
}

#Network security group
resource "azurerm_network_security_group" "nsg-bastion" {
  name = "nsg-bastion-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name = "ssh"
    priority = 101
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = "Internet"
    destination_port_range     = "22"
    destination_address_prefix = "*"
  }
}

#Network Security Groups Association
resource "azurerm_subnet_network_security_group_association" "nsg-asso-bastion" {
  subnet_id = azurerm_subnet.bastion.id
  network_security_group_id = azurerm_network_security_group.nsg-bastion.id
}
