# Application Gateway resources
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

data "terraform_remote_state" "main_infra" {
  backend = "local"

  config = {
    path = "../terraform.tfstate"
  }
}

locals {
 frontend_ip_conf_pub_name = "frontend_ip_conf_public" 
 frontend_port_6443_name = "https-6443"
 frontend_port_80_name = "http-80"
 frontend_port_443_name = "https-443"
 ssl_certificate_api_name = "api-cert"
 ssl_certificate_apps_name = "apps-cert"
 listener_api_name = "api"
 listener_apps_name = "apps"
 backend_pool_api_name = "api"
 backend_pool_apps_name = "apps-ssl"
 api_probe_name = "api_probe"
 apps_probe_name = "apps_probe"
 http_setting_api_name = "api"
 http_setting_apps_name = "apps"
 http_setting_apps-ssl_name = "apps-ssl"
}

#Subnet to place app gateway in
resource "azurerm_subnet" "app_gateway_subnet" {
  name = "appgateway-${data.terraform_remote_state.main_infra.outputs.suffix}"
  resource_group_name = data.terraform_remote_state.main_infra.outputs.network_resource_group
  virtual_network_name = data.terraform_remote_state.main_infra.outputs.virtual_network
  address_prefixes = ["10.0.10.0/24"]
  }

#Public IP for the App Gateway Frontend
resource "azurerm_public_ip" "app_gateway_pubip" {
  name = "app_gateway_pubip"
  resource_group_name = data.terraform_remote_state.main_infra.outputs.network_resource_group
  location = data.terraform_remote_state.main_infra.outputs.region_name
  sku = "Standard"
  allocation_method = "Static"
}

#Application Gateway
resource "azurerm_application_gateway" "app_gateway" {
  name = "app_gateway-${data.terraform_remote_state.main_infra.outputs.suffix}"
  resource_group_name = data.terraform_remote_state.main_infra.outputs.network_resource_group
  location = data.terraform_remote_state.main_infra.outputs.region_name

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
    capacity = 4
  }
  
  gateway_ip_configuration {
    name = "app_gateway_pubip_config"
    subnet_id = azurerm_subnet.app_gateway_subnet.id
  }

  frontend_ip_configuration {
    name = local.frontend_ip_conf_pub_name
    public_ip_address_id = azurerm_public_ip.app_gateway_pubip.id
  }

  frontend_port {
    name = local.frontend_port_80_name
    port = 80
  }

  frontend_port {
    name = local.frontend_port_443_name 
    port = 443
  }

  frontend_port {
    name = local.frontend_port_6443_name 
    port = 6443
  }

#PKCS12 certificate for api listener containing both private and public keys
  dynamic "ssl_certificate" {
    for_each = var.publish_api ? [1] : []
    content {
      name = local.ssl_certificate_api_name
      data = filebase64("${path.module}/api-cert.pfx")
      password = var.api_cert_passwd
    }
  }

#PKCS12 certificate for apps listener containing both private and public keys
  ssl_certificate {
    name = local.ssl_certificate_apps_name
    data = filebase64("${path.module}/apps-cert.pfx")
    password = var.apps_cert_passwd
  }

  dynamic "http_listener" {
    for_each = var.publish_api ? [1] : []
    content {
      name = local.listener_api_name 
      frontend_ip_configuration_name = local.frontend_ip_conf_pub_name
      frontend_port_name = local.frontend_port_6443_name
      protocol = "Https"
      ssl_certificate_name = local.ssl_certificate_api_name
    }
  }

  http_listener {
    name = local.listener_apps_name
    frontend_ip_configuration_name = local.frontend_ip_conf_pub_name
    frontend_port_name = local.frontend_port_80_name
    protocol = "Http"
  }

  dynamic "http_listener" {
    for_each = toset(var.ssl_listener_hostnames)
    content {
      name = "apps-ssl-listener-${http_listener.value}"
      frontend_ip_configuration_name = local.frontend_ip_conf_pub_name
      frontend_port_name = local.frontend_port_443_name
      protocol = "Https"
      ssl_certificate_name = local.ssl_certificate_apps_name
      host_name = "${http_listener.value}.apps.${var.cluster_domain}"
    }
  }

  dynamic "backend_address_pool" {
    for_each = var.publish_api ? [1] : []
    content {
      name = local.backend_pool_api_name
      ip_addresses = ["${var.api_lb_ip}"]
    }
  }

  backend_address_pool {
    name = local.backend_pool_apps_name
    ip_addresses = ["${var.apps_lb_ip}"]
  }

  dynamic "trusted_root_certificate" {
    for_each = var.publish_api ? [1] : []
    content {
      name = "api_root_CA"  
      data = filebase64("${path.module}/api-root-CA.cer")
    }
  }

  trusted_root_certificate {
    name = "apps_root_CA"  
    data = filebase64("${path.module}/apps-root-CA.cer")
  }

  dynamic "probe" {
    for_each = var.publish_api ? [1] : []
    content {
      name = local.api_probe_name
      protocol = "Https"
      host = "api.${var.cluster_domain}"
      path = "/readyz"
      interval = 30
      timeout = 30
      unhealthy_threshold = 3
    }
  }  

  dynamic "backend_http_settings" {
    for_each = var.publish_api ? [1] : []
    content {
      name = local.http_setting_api_name 
      protocol = "Https"
      port = 6443
      cookie_based_affinity = "Disabled"
      request_timeout = 20
      host_name = "api.${var.cluster_domain}"
      trusted_root_certificate_names = ["api_root_CA"]
      probe_name = local.api_probe_name
    }
  }

  probe {
    name = local.apps_probe_name
    protocol = "Http"
    host = "console-openshift-console.apps.${var.cluster_domain}"
    path = "/"
    interval = 30
    timeout = 30
    unhealthy_threshold = 3
  }  

  backend_http_settings {
    name = local.http_setting_apps_name 
    protocol = "Http"
    port = 80
    cookie_based_affinity = "Disabled"
    request_timeout = 20
    probe_name = local.apps_probe_name
  }

  dynamic "probe" {
    for_each = toset(var.ssl_listener_hostnames)
    content {
      name = "apps-ssl-probe-${probe.value}"
      protocol = "Https"
      host = "${probe.value}.apps.${var.cluster_domain}"
      path = "/"
      interval = 30
      timeout = 30
      unhealthy_threshold = 3
  
      match {
        status_code = ["200-399","403"]
      }
    }
  }  

  dynamic "backend_http_settings" {
    for_each = toset(var.ssl_listener_hostnames)
    content {
      name = "aps-ssl-${backend_http_settings.value}"
      protocol = "Https"
      port = 443
      cookie_based_affinity = "Disabled"
      request_timeout = 20
      host_name = "${backend_http_settings.value}.apps.${var.cluster_domain}"
      trusted_root_certificate_names = ["apps_root_CA"]  
      probe_name = "apps-ssl-probe-${backend_http_settings.value}"
    }
  }

  dynamic "request_routing_rule" {
    for_each = var.publish_api ? [1] : []
    content {
      name = "routing_rule_api"
      rule_type = "Basic"
      http_listener_name = local.listener_api_name 
      backend_address_pool_name = local.backend_pool_api_name 
      backend_http_settings_name = local.http_setting_api_name
    }
  }

  request_routing_rule {
    name = "routing_rule_apps"
    rule_type = "Basic"
    http_listener_name = local.listener_apps_name
    backend_address_pool_name = local.backend_pool_apps_name 
    backend_http_settings_name = local.http_setting_apps_name
  }

  dynamic "request_routing_rule" {
    for_each = toset(var.ssl_listener_hostnames)
    content {
      name = "apps-ssl-${request_routing_rule.value}"
      rule_type = "Basic"
      http_listener_name = "apps-ssl-listener-${request_routing_rule.value}"
      backend_address_pool_name = local.backend_pool_apps_name 
      backend_http_settings_name = "aps-ssl-${request_routing_rule.value}"
    }
  }
}
