#NAT GATEWAY COMPONENTS

#Public IP for NAT gateway
resource "azurerm_public_ip" "nat_pub_ip" {
  name = "nat_pub_ip-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method            = "Static"
  sku                 = "Standard"
}

#Nat gateway
resource "azurerm_nat_gateway" "nat_gw" {
  name = "nat_gw-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  idle_timeout_in_minutes = 10
  sku_name                 = "Standard"
}

#Association between public IP and Nat gateway
resource "azurerm_nat_gateway_public_ip_association" "natgw_pubip_asso" {
  nat_gateway_id = azurerm_nat_gateway.nat_gw.id
  public_ip_address_id = azurerm_public_ip.nat_pub_ip.id
}

#Association between nat gateway and subnet masters
resource "azurerm_subnet_nat_gateway_association" "natgw_subnet_asso_masters" {
  subnet_id = var.subnet_masters_id
  nat_gateway_id = azurerm_nat_gateway.nat_gw.id
}

#Association between nat gateway and subnet workers
resource "azurerm_subnet_nat_gateway_association" "natgw_subnet_asso_workers" {
  subnet_id = var.subnet_workers_id
  nat_gateway_id = azurerm_nat_gateway.nat_gw.id
}
