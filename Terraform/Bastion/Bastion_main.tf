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


#BASTION VM

# Public IP
resource "azurerm_public_ip" "bastion_pub_ip" {
    name                         = "bastion_public_ip"
    location                     = var.location
    resource_group_name          = var.resource_group_name
    allocation_method            = "Dynamic"
}

# Network interface
resource "azurerm_network_interface" "bastion_nic" {
    name                      = "bastion_nic"
    location                  = var.location
    resource_group_name       = var.resource_group_name

    ip_configuration {
        name                          = "bastion_nic_config"
        subnet_id                     = azurerm_subnet.bastion.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.bastion_pub_ip.id
    }
}

#Network Security Groups Association
resource "azurerm_network_interface_security_group_association" "nsg-asso-bastion" {
  network_interface_id = azurerm_network_interface.bastion_nic.id
  network_security_group_id = azurerm_network_security_group.nsg-bastion.id
}

# Virtual machine
resource "azurerm_linux_virtual_machine" "bastion" {
    name                  = "bastion"
    location              = var.location
    resource_group_name   = var.resource_group_name
    network_interface_ids = [azurerm_network_interface.bastion_nic.id]
    size                  = "Standard_D4s_v4"
    computer_name  = "bastion"
    admin_username = "azureuser"
    disable_password_authentication = true

    os_disk {
        caching           = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }

    source_image_reference {
        publisher = "RedHat"
        offer     = "RHEL"
        sku       = "8-lvm-gen2"
        version   = "latest"
    }

    admin_ssh_key {
        username       = "azureuser"
        public_key     = file("${path.module}/ocp-install.pub")
    }
}
