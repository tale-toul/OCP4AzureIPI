#VARIABLES
variable "region_name" {
  description = "Azure Region to deploy resources"
  type = string
  default = "francecentral"
}

variable "create_bastion" {
  type = bool
  default = true
  description = "Determines if the bastion infrastructure will be deployed"
}

#LOCALS
locals {
suffix = "${random_string.strand.result}"
}
