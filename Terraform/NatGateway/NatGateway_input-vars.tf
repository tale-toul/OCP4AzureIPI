#Variables definition for Nat Gateway module

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

#Masters subnet id
variable "subnet_masters_id" {
  type = string
  description = "Masters subnet id"
}

#Workers subnet id
variable "subnet_workers_id" {
  type = string
  description = "Workers subnet id"
}
