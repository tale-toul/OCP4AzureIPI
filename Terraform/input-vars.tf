#VARIABLES

variable "cluster_name" {
  description = "This name is used as part of the name of some resource and will be assigned to the OCP cluster" 
  type = string
}

variable "region_name" {
  description = "Azure Region to deploy resources"
  type = string
  default = "francecentral"
}

variable "cluster_scope" {
  type = string
  default = "public"
  description = "Is the cluster public (accesible from the Internet) or private"

  validation {
    condition = var.cluster_scope == "public" || var.cluster_scope == "private"
    error_message = "The cluster_scope variable only allows the values: public or private."
  }
}

variable "outbound_type" {
  type = string
  default = "LoadBalancer"
  description = "Defines the networking method that cluster nodes will use to connect to the Internet (outbound traffic).  Can have the values: LoadBalancer, the installer will create a load balancer with outbound rules; and UserDefinedRouting, the outbound rules in the load balancer will not be created and the user must provide the outbound configuration, for example a NAT gateway"

  validation {
    condition = var.outbound_type == "LoadBalancer" || var.outbound_type == "UserDefinedRouting" 
    error_message = "The outbound_type variable only allows any of the values: LoadBalancer or UserDefinedRouting."
  }
}

variable "create_bastion" {
  type = bool
  default = true
  description = "Determines if the bastion infrastructure will be deployed"
}

#LOCALS
locals {
suffix = "${random_string.strand.result}"

#If the cluster is public (External) the network security group rules have an any (*) source address prefix, 
#if the cluster is private the source address prefix is the service tag VirtualNetwork (https://docs.microsoft.com/en-us/azure/virtual-network/service-tags-overview)
nsg_source_address = var.cluster_scope == "public" ? "*" : "VirtualNetwork"
}
