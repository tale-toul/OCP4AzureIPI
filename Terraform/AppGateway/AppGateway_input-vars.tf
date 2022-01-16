#Variables definition for Application Gateway module

#Private IP of the private load balancer for API access 
variable "api_lb_ip" {
  type = string
  description = "Private IP of the internal load balancer used for API access" 
  default = ""
}

#Private IP of the private load balancer for application access 
variable "apps_lb_ip" {
  type = string
  description = "Private IP of the internal load balancer used for application access" 
}

#Password to decrypt PKCS12 certificate for API listener
variable "api_cert_passwd" {
  type = string
  description = "Password to decrypt PKCS12 certificate for API listener"
  default = ""
  sensitive = true
}

#Password to decrypt PKCS12 certificate for APPS listener
variable "apps_cert_passwd" {
  type = string
  description = "Password to decrypt PKCS12 certificate for APPS listener"
  sensitive = true
}

variable "ssl_listener_hostnames" {
  type = list(string)
  description = "List of valid hostnames for the listener and http settings used to access applications in the *.apps domain when using TLS connections"
  default = []
}

variable "cluster_domain" {
  type = string
  description = "DNS domain used by cluster"
}

variable "publish_api" {
  type = bool
  default = false
  description = "Is the API entry point to be published?"
}
