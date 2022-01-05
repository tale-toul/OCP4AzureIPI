terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.90.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

#Provides a source to create a short random string 
resource "random_string" "strand" {
  length = 5
  upper = false
  special = false
}

#Resource group
resource "azurerm_resource_group" "resogroup" {
  name     = "ocp4-resogroup-${local.suffix}"
  location = var.region_name
}

#VNet 
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.suffix}"
  resource_group_name = azurerm_resource_group.resogroup.name
  location            = azurerm_resource_group.resogroup.location
  address_space       = ["10.0.0.0/16"]
}

#Subnets
resource "azurerm_subnet" "masters" {
  name = "masters-${local.suffix}"
  resource_group_name = azurerm_resource_group.resogroup.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = ["10.0.1.0/24"]
  }

resource "azurerm_subnet" "workers" {
  name = "workers-${local.suffix}"
  resource_group_name = azurerm_resource_group.resogroup.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = ["10.0.2.0/24"]
}

#Network security groups
resource "azurerm_network_security_group" "nsg-masters" {
  name = "nsg-masters-${local.suffix}"
  location            = azurerm_resource_group.resogroup.location
  resource_group_name = azurerm_resource_group.resogroup.name

  security_rule {
    name = "api"
    priority = 101
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = "${local.nsg_source_address}"
    destination_port_range     = "6443"
    destination_address_prefix = "*"
  }

  security_rule {
    name = "machprov"
    priority = 102
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = "${local.nsg_source_address}"
    destination_port_range     = "22623"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "nsg-workers" {
  name = "nsg-workers-${local.suffix}"
  location            = azurerm_resource_group.resogroup.location
  resource_group_name = azurerm_resource_group.resogroup.name

  security_rule {
    name = "http"
    priority = 500
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = "${local.nsg_source_address}"
    destination_port_range     = "80"
    destination_address_prefix = "*"
  }

  security_rule {
    name = "https"
    priority = 501
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = "${local.nsg_source_address}"
    destination_port_range     = "443"
    destination_address_prefix = "*"
  }
}

#Network Security Groups Associations
resource "azurerm_subnet_network_security_group_association" "nsg-asso-masters" {
  subnet_id = azurerm_subnet.masters.id
  network_security_group_id = azurerm_network_security_group.nsg-masters.id
}

resource "azurerm_subnet_network_security_group_association" "nsg-asso-workers" {
  subnet_id = azurerm_subnet.workers.id
  network_security_group_id = azurerm_network_security_group.nsg-workers.id
}

#Nat Gateway module
module "nat_gateway" {
  source = "./NatGateway"
  count = var.outbound_type == "UserDefinedRouting" ? 1 : 0

  resource_group_name = azurerm_resource_group.resogroup.name
  vnet_name = azurerm_virtual_network.vnet.name
  suffix = local.suffix
  location = azurerm_resource_group.resogroup.location
  subnet_masters_id = azurerm_subnet.masters.id
  subnet_workers_id = azurerm_subnet.workers.id
}

#Bastion module
module "bastion" {
  source = "./Bastion"
  count = var.create_bastion ? 1 : 0

  resource_group_name = azurerm_resource_group.resogroup.name
  vnet_name = azurerm_virtual_network.vnet.name
  suffix = local.suffix
  location = azurerm_resource_group.resogroup.location
}
