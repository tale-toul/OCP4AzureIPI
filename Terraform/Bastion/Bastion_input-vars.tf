#Variables definition

#Resource group name
variable "resource_group_name" {
  type = string
  description = "Name of resource group where the VNet is created"
}

#VNet name
variable "vnet_name" {
  type = string
  description = "Name of VNet"
}

#Random suffix string
variable "suffix" {
  type = string
  description = "Random string to identify resources"
}

#Azure region
variable "location" {
  type = string
  description = "Azure region where resources are deployed"
}
