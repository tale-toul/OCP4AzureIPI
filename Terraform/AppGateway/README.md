# Application Gateway Technicall Details 

## Dynamically Creating the blocks

### Creating the backend hostname with regular expressions

In the case of probes and backend http settings definitions for secure application routes, the hostname is built using a complex piece of terraform code:
```
  dynamic "probe" {
    for_each = toset(var.ssl_listener_hostnames)
    content {
      ...
      host = join(".", [regex("([^.]+)\\..+",probe.value)[0],"apps",var.cluster_domain])
      ...
...
  dynamic "backend_http_settings" {
    for_each = toset(var.ssl_listener_hostnames)
    content {
      ...
      host_name = join(".", [regex("([^.]+)\\..+",backend_http_settings.value)[0],"apps",var.cluster_domain])
      ...
```
The reason to build the backend hostname in this way is because the FQDN used by the external client may be different from the internal FQDN used by the Openshift route, for example the external FQDN of an application may be `app1.tale.net` while the internal may be app1.apps.jupiter.example.com.

In the terraform implementation:
* The short name must be the same in the external and internal names: __app1__
* The __apps__ subdomain is fixed for all internal routes.
* The cluster domain is extracted from the terraform variable: **cluster_domain**

The only changing part for every probe and http settings block is the short name of the application, which is extracted from the list of FQDN names defined in the variable __ssl_listener_hostnames__.  

To extract the hostname a regular expression is used: `regex("([^.]+)\\..+",backend_http_settings.value)`

The terraform function [regex](#https://www.terraform.io/language/functions/regex) is used to apply the regular expression.

The function contains two arguments: the regular expression and the string to apply it to.
* The regular expression is `([^.]+)\\..+`.  The parentheses delimit a capture group, only the text captured by the subexpression between them will be returned.  In this case the string from the beginning to the first dot in the FQDN, not including the dot.  `[^.]+` means any string of characters that doesn't contain a dot.  Then a dot should be found `\\.` plus any other characters `.+`.
* The string to match with the regular expression is contained in the for_each loop variable backend_http_settings.value and probe.value that changes on every iteration of the loop.  

Because the regular expression contains a capture group, the regex() function returns a list of results.  In this case there is only one capture group so the list will always have at most one element. That is way to convert the list into a string a position index meaning the first element is used: `regex()[0]`

To build the final string the [join](#https://www.terraform.io/language/functions/join) function is used, the delimiter between components is a dot "." and the list of components is made of the value returned by the regex() function which is the short hostname; the "apps" string; and the cluster domain as defined in the variable cluster_domain

Trying to use a string template to build the internal hostname resulted in an error.  The string template is easier to understand than the complex construct with the join function however it didn't work:
```
 on AppGateway-main.tf line 240, in resource "azurerm_application_gateway" "app_gateway":
│  240:       host_name = "${regex("([^.]+)\\..+",backend_http_settings.value)}.apps.${var.cluster_domain}"
│     ├────────────────
│     │ backend_http_settings.value is "prometheus-k8s-openshift-monitoring.apps.boxhill.bonya.net"
│ 
│ Cannot include the given value in a string template: string required.
```
