#VARIABLES
variable "region_name" {
  description = "Azure Region to deploy resources"
  type = string
  default = "France Central"
}

#LOCALS
locals {
suffix = "${random_string.strand.result}"
}
