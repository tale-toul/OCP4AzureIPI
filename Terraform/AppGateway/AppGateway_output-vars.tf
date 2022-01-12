#Application Gateway Output Variables

output "frontend_pub_ip" {
  value = azurerm_public_ip.app_gateway_pubip.ip_address 
  description = "Public IP address assigned to the Application Gateway"
}

output "backend_address_pools" {
  value = {
    for pool in azurerm_application_gateway.app_gateway.backend_address_pool:
    pool.name => pool.ip_addresses
  }
  description = "Backend address pools IP addresses"
}

output "listener_names"  {
  value = azurerm_application_gateway.app_gateway.http_listener[*].name
  description = "HTTP listener names"
}
