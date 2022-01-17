# Openshift 4 on Azure on existing VNet using IPI installer 

## Table of Contents
* [Introduction](#introduction)
* [Prerequisites](#prerequisites)
  * [Terraform installation](#terraform-installation)
  * [Creating a Service Principal ](#creating-a-service-principal) 
* [Outbound traffic configuration](#outbound-traffic-configuration)
* [Cluster Deployment Instructions](#cluster-deployment-instructions)
* [Create the infrastructure with Terraform](#create-the-infrastructure-with-terraform)
  * [Terraform initialization](#terraform-initialization)
  * [Login into Azure](#login-into-azure)
  * [Variables definition](#variables-definition)
  * [SSH key](#ssh-key)
  * [Deploy the infrastructure with Terraform](#deploy-the-infrastructure-with-terraform)
* [Bastion infrastructure](#bastion-infrastructure)
  * [Conditionally creating the bastion infrastructure](#conditionally-creating-the-bastion-infrastructure)
  * [Destroying the bastion infrastructure](#destroying-the-bastion-infrastructure)
* [Prepare the bastion host to install Openshift](#set-up-the-bastion-host-to-install-openshift)
* [OCP Cluster Deployment](#ocp-cluster-deployment)
* [Cluster Decommission Instructions](#cluster-decommission-instructions)
* [Accessing a Private OpenShift Cluster from The Internet](#accessing-a-private-openshift-cluster-from-the-internet)
  * [Variables Definition](#variables-definition)
    * [Obtaining the Load Balancers IP addresses](#obtaining-the-load-balancers-ip-addresses)
  * [Application Gateway Deployment](#application-gateway-deployment)
    * [Obtaining the Certificate for API and Application Secure Routes](#obtaining-the-certificate-for-api-and-application-secure-routes)
  * [Accessing the Openshift Cluster through the Application Gateway](#accessing-the-openshift-cluster-through-the-application-gateway)
  * [Updating the Configuration](#updating-the-configuration)
  * [Application Gateway Decommission](#application-gateway-decommission)
* [Configuring DNS resolution with dnsmasq](#configuring-dns-resolution-with-dnsmasq)

## Introduction

The instructions and code in this repository can be used as an example to deploy an Openshift 4 cluster on a pre existing VNet in Azure.  The installer used here is the IPI installer.

The Openshift cluster deployed using this repository can be publc or private:
* A public cluster is fully accessible from the Internet.  
* A private cluster is not accessible from outside the VNet where it is created unless additional configurations are put in place to allow clients to connect from other VNets or the Internet at large.  This repository provides an [example of such configuration](#accessing-a-private-openshift-cluster-from-the-internet) using an Application Gateway to turn the private cluster, or parts of it public.

    Why create a private cluster and then make it public if it can more easily be installed as public from the beginning.  Several reasong may exist: Hidding the complex DNS domain used by the cluster and instead publish a simpler one (myapp.apps.cluster1.example.com vs myapp.example.com); Limiting the number of public applications to a subset of the all applications running in the cluster; Keeping the API endpoint private; Keeping the cluster private until it is fully configured and ready for use; Hidding a multicluster infrastructure behind a single point of access; etc.

The VNet and related Azure resources required to deploy the OCP cluster are created using terraform. 
The OCP cluster can be [public](https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-vnet.html), that is accessible from Intenet; or [private.](https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-private.html) only accessible from the VNet where it is deployed.

The Azure resources required to deploy the Openshift 4 cluster is an existing VNet are:
* Resource Group.- That contains the following resources
* VNet
* Subnets.- Two subnets are needed, one for the control plane (masters) and one for the worker nodes.
* Network security groups.- One for each of the above subnets with its own security rules.
* Resources and configuration for the oubound network traffic from the cluster nodes to the Internet.- The requirement for these resources depends on the value of the variable [outboundType](#outbound-traffic-configuration) in the install-config.yaml file.

These resources are usually created by the IPI installer, to make it aware that they already exist and should not be created during cluster intallation the following variables must be defined in the __platform.azure__ section in the install-config.yaml file:

* networkResourceGroupName.- Contains the name of the resource group where the previously mentioned, user provided network resources exist.
* virtualNetwork.- The name of the VNet to be used
* controlPlaneSubnet.- The name of the subnet where master nodes will be deployed
* computeSubnet.- The name of the subnet where worker nodes will be deployed
* outboundType.- The type of [outboundType](#outbound-traffic-configuration) network configuration to use

```
...
platform:
  azure:
    networkResourceGroupName: ocp4-resogroup-gohtd
    virtualNetwork: vnet-gohtd
    controlPlaneSubnet: masters-gohtd
    computeSubnet: workers-gohtd
    outboundType: Loadbalancer
...
```
## Prerequisites
Before attempting to deploy the Openshift cluster make sure to fulfill the following prerequisites:
* A public DNS zone must exist in Azure and the account used to deploy the cluster must have permissions to create records in it. [More details](#https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-account.html#installation-azure-network-config_installing-azure-account)
* The default limits in a newly created Azure account are too low to deploy an Openshift cluster, make sure this limits have been extended. [More details](#https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-account.html#installation-azure-limits_installing-azure-account)
* Create a service principal with the roles of _Owner_ and _User Access Administrator_, and use it to deploy the Openshift cluster. [Creating a Service Principal](#creating-a-service-principal)
* A working terraform installation in the host where the infrastructure is going to be deployed from. [Terraform installation](#terraform-installation)
* A working ansible installation in the host where the infrastructure is going to be deployed from.

### Terraform installation

The installation of terraform is as simple as downloading a zip compiled binary package for your operating system and architecture from:

`https://www.terraform.io/downloads.html`

Then unzip the file:

```shell
 # unzip terraform_0.11.8_linux_amd64.zip 
Archive:  terraform_0.11.8_linux_amd64.zip
  inflating: terraform
```

Place the binary somewhere in your path:

```shell
 # cp terraform /usr/local/bin
```

Check that it is working:

```shell
 # terraform --version
```
### Creating a Service Principal 
For more details visit the [official Openshift documentation](#https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-account.html#installation-azure-service-principal_installing-azure-account)

This instruction use the _az_ command line tool.
* Create the service principal and assing it the _Contributor_ role and a name, in the example *ocp_install_sp*. Save the _appId_ and password values, they are needed in following steps:

        $ az ad sp create-for-rbac --role Contributor --name ocp_install_sp

 
* Assign the _User Access Administrator_ role to the service principal just created. Replace \<appId\> with the value obtained in the first command:

        $ az role assignment create --role "User Access Administrator" \
        --assignee-object-id $(az ad sp list --filter "appId eq '<appId>'" \ 
        | jq '.[0].objectId' -r)


## Outbound traffic configuration
The network resources and configuration allowing the cluster nodes to connect to the Internet (outbound traffic) depend on the value of the variable __outboundType__ in the install-config.yaml file. This configuration is independent from that of the inbound cluster traffic, whether this is a public or private cluster.

The __outboundType__ variable can take only two possible values: Loadbalancer and UserDefinedRouting:
* **LoadBalancer**.- The IPI installer will create an outbound rule in the public load balancer to allow outgoing connections from the nodes to the Internet.  If the the cluster is public, the load balancer is used for routing both inbound traffic from the Internet to the nodes and outbound traffic from the nodes to the Internet.  If the cluster is private there is no inbound traffic from the Internet to the nodes, but the load balancer will still be created and will only be used for outbound traffic from the nodes to the Internet.
* **UserDefinedRouting**.- The necessary infrastructure and configuration to allow the cluster nodes to connect to the internet must be in place before running the IPI installer, different options exit in Azure for this: NAT gateway; Azure firewall; Proxy server; etc.  In this repository the terraform template creates a NAT gateway if the **outbound_type** variable contains the value _UserDefinedRouting_.  

When outboundType = UserDefinedRouting, a load balancer is still created but contains no frontend IP address, load balancing rules or outbound rules, so it serves no purpose.  A fully functional internal load balancer is always created for access to the API service and applications only from inside the VNet.

## Cluster Deployment Instructions

The deployment process consists of the following points:

* [Create the infrastructure components in Azure](#create-the-infrastructure-with-terraform).- The VNet and other components are created using terraform.
* [Set up installation environment](#set-up-the-bastion-host-to-install-openshift).- The bastion host is prepared to lauch the openshift installer from it.
* [Run the Openshift installer](#ocp-cluster-deployment)

### Create the infrastructure with Terraform
Terraform is used to create in Azure the network infrastructure resources required to deploy the Openshift 4 cluster into.  The [terraform Azure provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) is used.  

#### Terraform initialization

Check for any updates and initialize terraform plugins and modules:

```shell
  $ cd Terraform
  $ terraform init
  
  Initializing the backend...
  
  Initializing provider plugins...
  - Finding latest version of hashicorp/aws...
  - Finding latest version of hashicorp/random...
  - Installing hashicorp/aws v3.65.0...
  - Installed hashicorp/aws v3.65.0 (signed by HashiCorp)
  - Installing hashicorp/random v3.1.0...
  - Installed hashicorp/random v3.1.0 (signed by HashiCorp)
  
  Terraform has created a lock file .terraform.lock.hcl to record the provider
  selections it made above. Include this file in your version control repository
  so that Terraform can guarantee to make the same selections by default when
  you run "terraform init" in the future.
  
  Terraform has been successfully initialized!
  
  You may now begin working with Terraform. Try running "terraform plan" to see
  any changes that are required for your infrastructure. All Terraform commands
  should now work.
  
  If you ever set or change modules or backend configuration for Terraform,
  rerun this command to reinitialize your working directory. If you forget, other
  commands will detect it and remind you to do so if necessary.
```

#### Login into Azure
Before running terraform to create resources, a user with enough permissions must be authenticated with Azure, there are several options to perform this authentication as explained in the terraform [documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_certificate) for the Azure resource provider.  The simplest authentication method uses the Azure CLI:

* Install __az__ [client](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli). On [RHEL]((https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=dnf#install))

* Login to azure with:
```  
$ az login
```  
Once successfully loged in, the file __~/.azure/azureProfile.json__ is created containing credentials that are used by the az CLI and terraform to run commands in Azure.  This credentials are valid for the following days so no further authentication with Azure is required for a while.

#### Variables definition
Some of the resources created by terraform can be adjusted via the use of variables:
* **cluster_name**.- A unique name for the Openshift cluster.  

    No default value so it must be specified everytime the _terraform_ command is executed. 

        cluster_name: jupiter

* **region_name**.- Contains the short name of the Azure region where the resources, and the Openshift cluster, will be created. The short name of the regions can be obtained from the __Name__ column in the output of the command `az account list-locations -o table`.  

    No default value so it must be specified everytime the _terraform_ command is executed. 

        region_name: "francecentral"

* **create_bastion**.- Boolean used to determine if the bastion infrastructure will be created or not.

    Default value **true**

        create_bastion: false

* **cluster_scope**.- Used to define if the cluster will be public (accessible from the Internet) or private (not accessible from the Internet).  

    Possible values: _public_ or _private_. 

    Default value: _public_

        cluster_scope: public

* **outbound_type**.- Defines the networking method that cluster nodes use to connect to the Internet (outbound traffic).  

    Possible values: __LoadBalancer__, the installer will create a load balancer with outbound rules, even if the cluster scope is private; and _UserDefinedRouting_, the outbound rules in the load balancer will not be created and the user must provide the outbound configuration, for example a NAT gateway".  

    Default value:_LoadBalancer_.

        outbound_type: LoadBalancer

#### SSH key
Regardless of whether the the bastion infrastructure is going to be created ([Conditionally creating the bastion infrastructure](#conditionally-creating-the-bastion-infrastructure)), an ssh key is needed to connect to the bastion VM and the OCP cluster nodes.

Terraform expects a file containing the public ssh key in a file at __Terraform/Bastion/ocp-install.pub__.  This can be an already existing ssh key or a new one can be [created](https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-private.html#ssh-agent-using_installing-azure-private):

```
$ ssh-keygen -o -t rsa -f ocp-install -N "" -b 4096
```
The previous command will generate two files: ocp-install containing the private key and ocp-install.pub containing the public key.  The private key is not protected by a passphrase.

#### Deploy the infrastructure with Terraform
To create the infrastructure run the __terraform apply__ command.  Enter "yes" at the prompt:

```  
$ cd Terraform
$ terraform apply -var="region_name=West Europe"
...
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```  
Resource creation will be completed successfully when a message like the following appears:
```  
Apply complete! Resources: 9 added, 0 changed, 0 destroyed.

Outputs:
...
```  
Save the command used to create the infrastructure for future reference.  The same variable definitions must be used when [destroying the resources](#cluster-decommissioning-instructions).

```  
$ echo "!!" > terraform_apply.txt
```  
## Bastion Infrastructure
Reference documentation on how to create the VM with terraform in Azure: \[[1](https://docs.microsoft.com/en-us/azure/developer/terraform/create-linux-virtual-machine-with-infrastructure)\] and \[[2](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine)\]

In the default configuration, with variable `create_bastion=true` a bastion host is created in its own subnet and gets assigned a network security rule that allows ssh connections into it.  It is intended to run the OCP 4 installer from it, and once the OCP cluster is installed it can be used to access the cluster using the __oc__ cli.

The bastion infrastructure is created from a module in terraform so it can be [conditionally created](#conditionally-creating-the-bastion-infrastructure) and [easily destroyed](#destroying-the-bastion-infrastructure) once it is not needed anymore.

The bastion VM gets both public and private IP addresses assigned to its single NIC. The network security group is directly associated with this NIC.

The operating system disk image used in the bation VM is the latest version of RHEL 8.  The same definition can be used irrespective of the region where the resources will be deployed.  The az cli commands used to collect the information for the definition can be found [here](https://docs.microsoft.com/en-us/cli/azure/vm/image?view=azure-cli-latest), for example:

```
$ az vm image list-publishers
$ az vm image list-offers -l "West Europe" -p RedHat
$ az vm image list-skus -l "West Europe" -p RedHat -f rh_rhel_8_latest
$ az vm image list -l "West Europe" -p RedHat --all -s 8-lvm-gen2
$ az vm image show -l "West Europe" -p RedHat -s 8-lvm-gen2 -f RHEL --version "8.5.2021121504"
```

To access the bastion VM using ssh, a public ssh key is injected during creation, this ssh key is expected to be found in a file called __ocp-install.pub__ in the __Terraform/Bastion__ directory.

### Conditionally creating the bastion infrastructure
A boolean variable is used to decide if the bastion infrastructure will be created or not.  The bastion infrastructure may not be required for example because the Openshift intaller is going to be run from an already existing host.

The variable is called __create_bastion__ and its default value is __true__, the bastion will be created, to skip the creation of the bastion infrastructure assing the value __false__ to the variable:

```
$ terraform apply -var="create_bastion=false"
```

WARNING.  Once the resources are created, the Terraform directory contains the state information that would be required to update or remove these resources using terraform.  Keep this directory and its files safe

### Destroying the bastion infrastructure
The bastion infrastructure is created by an independent module so it can be destroyed without affecting the rest of the resources.  This is useful to reduce costs and remove unused resources once the Openshift cluster has been deployed.

WARNING. Before removing the bastion virtual machine backup the OCP4 directory from which the Openshift installer was run, this is required to orderly remove the Openshift cluster.  Treat this backup as sensitive information as this contains the kubeadmin password and an X509 certificate which can be used to access the cluster with admin privileges.

The command to destroy only the bastion infrastructure is:
```
$ terraform destroy -target module.bastion
```
__WARNING__ If the __-target__ option is not used, terraform will delete all resources.

The option `-target module.<name>` is used to affect only a particular module in the terraform command

## Prepare the bastion host to install Openshift
Ansible is used to prepare the bastion host so the Openshift 4 cluster installation can be run from it.  Before running the playbook some prerequisites must be fullfilled:

Define the following variables in the file **Ansible/group_vars/all/cluster-vars**:
* **DNS base domain**.- This domain is used to access the Openshift cluster and the applications running in it.  In the case of a _public_ cluster, this DNS domain must exist in an Azure resource group.  In the case of a private cluster, a private domain will be created, there is no need to own that domain since it will only exist in the private VNet where the cluster is deployed.  The full domain is built as `<cluster name>.<base domain>` so for example if cluster name is __jupiter__ and base domain is __example.com__ the full cluster DNS domain is __jupiter.example.com__.  Assing the domain name to the variable **base_domain**.
```
base_domain: example.com
```
* **Base domain resource group**.- The Azure resource group name where the base domain exists.  In a private cluster this variable need not be defined.  Assing the name to the variable **base_domain_resource_group**
```
base_domain_resource_group: waawk-dns
```
* **Number of compute nodes**.- The number of compute nodes that the installer will create. Assing the number to the variable **compute_replicas**.
```
compute_replicas: 3
```
Download the Pull secret, Openshift installer and oc cli from [here](https://cloud.redhat.com/openshift/install), uncompress the installer and oc cli, and copy all these files to __Ansible/ocp_files/__

The inventory file for ansible containing the _[bastion]_ group is created by the ansible playbook itself so there is no need to create this file.

The same ssh public key used for the bastion host is injected to the Openshift cluster nodes, there is no need to provide a specific one.

Run the playbook:
```
$ ansible-playbook -vvv -i inventory setup_bastion.yaml
```
If anything goes wrong during the playbook execution, the messages generated by ansible can be found in the file __Ansible/ansible.log__

## OCP Cluster Deployment
Connect to the bastion host using ssh and enter the __OCP4__ directory. Use its public IP and the private part of the ssh key injected installed in the bastion VM.  The bastion VM can be found in several places, for example in the terraform output:
```
$ cd Terraform
$ terraform output bastion_public_ip
20.43.63.15
$ ssh -i ~/.ssh/ocp_install azureuser@20.43.63.15
$ cd OCP4
```
The Openshift installer, oc cli and a directory with the cluster name should be found here:
```shell
$ ls -F
jupiter/  oc  openshift-install
```
The directory contains the configuration file __install-config.yaml__, review and modify the file as required.

Before running the installer backup the install-config.yaml because the installer removes it as part of the installation process, and also run the installer in a tmux session so the terminal doesn't get blocked for around 40 minutes, which is the time the installation needs to complete.

```
$ cp jupiter/install-config.yaml .
$ tmux
```
Run the Openshift installer, it will prompt for the Azure credentials required to create all resources, after that the installer starts creating the cluster components:
```
$ ./openshift-install create cluster --dir jupiter
? azure subscription id 9cf87ea-3bf1-4b1a-8cc3-2aabe4cc8b98
? azure tenant id 6d4c6af4-d80b-4f9a-b169-4b4ec1aa1480
? azure service principal client id 0c957bc0-fbf9-fa60-6a5e-38a8bcc2e919
? azure service principal client secret [? for help] **********************************
INFO Saving user credentials to "/home/azureuser/.azure/osServicePrincipal.json" 
INFO Credentials loaded from file "/home/azureuser/.azure/osServicePrincipal.json" 
INFO Consuming Install Config from target directory 
INFO Creating infrastructure resources...
```
Alternatively an existing _osServicePrincipal.json_ file containing the credentials can be copied to the bastion host and placed at _/home/azureuser/.azure/osServicePrincipal.json_.  In this case the Openshift installer will not ask for the credentials and use the file instead.

The installation process will take more than 40 minutes.  The progress can be followed by tailing the *.openshift_install.log* :
```
$ tail -f OCP4/jupiter/.openshift_install.log
```
### Accessing the bootstrap node
In the first stages of the installation process a bootstrap node is created.  Sometimes it maybe desired to connect to this bootstrap node to watch this part of the installation or for debugging reasons.

The IPI installer creates a network security group and adds a rule to allow ssh connection to the boostrap node, however in an installation where the VNet, subnets, network security groups, etc. are provided by the user, the network security group created by the IPI installer is only applied to the bootstrap's network interface and not to the subnet where it is "connected".

On the other hand, the network security group created by terraform in this repository does not contain a similar security rule allowing ssh connctions to the bootstrap host, this is to increase security, specially considering that the bootstrap node is ephemeral and will be destroyed after it serves it purpose.

The bootstrap node is therefore not accessible via ssh from the Internet.

It is possible to ssh into the bootstrap from the bastion host, if this was created, or from any other VM running in the same VNet:
* Connect to the bastion host using ssh

        $ ssh -i ~/.ssh/ocp_install azureuser@20.43.63.15

* Get the private IP of the bootstrap node.  This can be easily found in the Azure portal for example.

* Connect to the bootstrap node

        $ ssh core@10.0.1.5

## Cluster Decommission Instructions
Deleting the cluster is a multi step process:

* Delete the components created by the openshift-install binary, run this command in the directory the installation was run from.  If the installation was run in the bastion host and it has been previously deleted, recover a backup of the __/home/azureuser/OCP4__ directory containing the status files required by the Openshift installer:
```
$ ./openshift-install destroy cluster --dir jupiter
```
* Delete the components created by terraform, use the terraform destroy command with the same variable definitions that were used when the resources were created. This command should be run from the same directory from which the terraform apply command was run:
```
$ cd Terraform
$ terraform destroy -var region_name="germanywestcentral" -var cluster_scope="private"
```
* If an [Application Gateway](#accessing-a-private-openshift-cluster-from-the-internet) has been created using the terraform module in this repository, remove it following the instruction in [this section ](#application-gateway-decommission)

## Accessing a Private OpenShift Cluster from The Internet
If the Openshift cluster deployed following the instructions in this repository is private, the API and any applications deployed in it are not accessible from the Internet.  This may be the desired state right after installation, but at a later time, when the cluster is fully set up and production applications are ready, it is possible that a particular set of applications and even the API endpoint are expected to be publicly available.  

There are many options to make the applications and API endpoint publicly available, this repository includes a terraform module that can be used for such purpose, it can be found in the directory __Terraform/AppGateway__.  This module creates an [Azure application gateway](https://docs.microsoft.com/en-us/azure/application-gateway/) that provides access to the applications running in the cluster, and optionally to the API endpoint.

To successfully deploy the Application Gateway using the terraform template in this repository, the Azure infrastructure must also be deployed using the terraform templates in this repository, and the Openshift cluster must be already running.

### Variables Definition
The following variables are used to pass information to terraform so the Application Gateway can be created and set up.  Add the variables definition to a file in the __Terraform/AppGateway__ directory, for example **AppGateway_vars**, and later call it in with the option `-var-file AppGateway_vars`.

* **publish_api**.- This boolean variable determines if the API entry point is to be published or not.  

    This variable is not required since it has a default value.

    Default value is __false__, the API endpoint will not be made public.
```
publish_api = true
```
* **api_lb_ip**.- Private IP of the internal load balancer used for API access.  See [Obtaining the Load Balancers IP addresses](#obtaining-the-load-balancers-ip-addresses) to learn how to obtain this IP.

    This variable is not required if the API endpoint is not going to be made public.  

    No default value.
```
api_lb_ip = "10.0.1.4"
```
* **apps_lb_ip**.- Private IP of the internal load balancer used for application access.  See [Obtaining the Load Balancers IP addresses](#obtaining-the-load-balancers-ip-addresses) to learn how to obtain this IP.

    This variable is always required.  

    No default value.
```
apps_lb_ip = "10.0.2.8"
```
* **api_cert_passwd**.- Password to decrypt PKCS12 certificate for API listener. 

    This variable is not required if the API endpoint is not going to be made public.

    No default value.
```
api_cert_passwd = "l3l#ah91"
```
* **apps_cert_passwd**.- Password to decrypt PKCS12 certificate for APPS listener.  

    This variable is always required.

    No default value.
```
apps_cert_passwd = "er4a9$C"
```
* **ssl_listener_hostnames**.- List of valid hostnames to access applications in the \*.apps domain when using TLS connections.  If this variable is not defined, no secure routes will be published.

    This variable in not required.

    No default value.
```
ssl_listener_hostnames = [ "httpd-example-caprice", 
                          "oauth-openshift",
                          "console-openshift-console",
                          "grafana-openshift-monitoring",
                          "prometheus-k8s-openshift-monitoring",
                        ]
```
* **cluster_domain**.- DNS domain used by cluster.  Consists of *cluster_name* + *cluster_domain*.  

    This variable is always required.

    No default value.
```
cluster_domain = "jupiter.example.com"
```

#### Obtaining the Load Balancers IP addresses
The variables *api_lb_ip* and *apps_lb_ip* described in [Variables Definition](#variables-definition) can be obtained from the Azure portal or using the following commands:

* Get the list of load balancers in the resource group created by the IPI installer.  The LB with _internal_ in its name is the one of interest here, the other LB is not even functional in a private cluster:
```
$ az network lb list -g lana-l855j-rg -o table
Location            Name                 ProvisioningState    ResourceGroup    ResourceGuid
------------------  -------------------  -------------------  ---------------  ------------------------------------
germanywestcentral  lana-l855j           Succeeded            lana-l855j-rg    73c41f07-886c-46f1-b4cc-007b64924ff4
germanywestcentral  lana-l855j-internal  Succeeded            lana-l855j-rg    9a4d37c9-b139-479b-9905-e12743a3ac47
```
* Get the frontend IPs associated with the internal LB, the one with the name _internal-lb-ip-v4_ is the IP for the API endpoint, the one with the long string of random characters is the IP for application access:
```
$ az network lb frontend-ip list -g lana-l855j-rg --lb-name lana-l855j-internal -o table
Name                              PrivateIpAddress    PrivateIpAddressVersion    PrivateIpAllocationMethod    ProvisioningState    ResourceGroup
--------------------------------  ------------------  -------------------------  ---------------------------  -------------------  ---------------
internal-lb-ip-v4                 10.0.1.4            IPv4                       Dynamic                      Succeeded            lana-l855j-rg
a0a66b12128ec4f33bbf3fb705e48e9e  10.0.2.8            IPv4                       Dynamic                      Succeeded            lana-l855j-rg
```
  Further details for the IPs can be obtained using a command like:
```
$ az network lb frontend-ip show -g lana-l855j-rg --lb-name lana-l855j-internal -n internal-lb-ip-v4|jq
```

### Application Gateway Deployment

The commands explained in this section must be run in the directory __Terraform/AppGateway__, in the same copy of the repository that was used to deploy the infrastructure used to install the Openshift cluster, this is because the AppGateway terraform module consumes information generated by terraform in its previous execution.

Follow the next steps to create the Application Gateway:

* Create a file to hold the variables detailed in the [Variables Definition](#variables-definition) section, for example *AppGateway_varsf*.

* Choose whether the API endpoint will be made public or not by assigning _true_ or _false_ to the variable **publish_api**, _false_ being the default value.

    If the API will not be public the following variables don't need to be defined: **publish_api**; **api_lb_ip**; **api_cert_passwd**.  The certificate file __api-cert.pfx__ is also not required in this case.

    The API endpoint can be publish or unpublish at anytime just by changing the value of the **publish_api** variable and rerunning the AppGateway terraform module.  In case of publishing the API, the variables **api_lb_ip**; **api_cert_passwd** must be defined and the certificate file __api-cert.pfx__ must be put in place.

* Obtain the IP addresses to assing to **apps_lb_ip**, and to **api_lb_api** if required, instructions on how to get this information can be found in the section [Variables definition](#variables-definition).

* Define the variable **ssl_listener_hostnames** with a list of short hostnames, without the DNS domain, of the Openshift application secure routes to be published using the _https_ protocol.  This list should at least contain the following names: "oauth-openshift", "console-openshift-console", "grafana-openshift-monitoring", "prometheus-k8s-openshift-monitoring".  

    If additional secure routes are required at a later time, just add the names to the list and rerun the AppGateway terraform module.

* Define the variable **cluster_domain** with the DNS domain used by the Openshift cluster.

* Obtain the certificates required to encrypt the secure connections with the cluster.  Two sets of certificates are required, one for the API endpoint and another one for the applications using secure routes.  If the API endpoint is not public, its certificate set is not required.  See [Obtaining the Certificate for API and Application Secure Routes](#obtaining-the-certificate-for-api-and-application secure routes) for instructions on how to obtain the certificates. 

    The terraform template expects to find the API endpoint PKCS12 certificate in a file called __api-cert.pfx__ and the PKCS12 certificate for application secure routes in a file called __apps-cert.pfx__, both in the directory __Terraform/AppGateway__.

A complete variables file example looks like this:
```
$ cat AppGateway_vars
publish_api = true
api_lb_ip = "10.0.1.4"
apps_lb_ip = "10.0.2.8"
api_cert_passwd = "l3l#ah91""
apps_cert_passwd = "er4a9$C""
ssl_listener_hostnames = [ "httpd-example-caprice", 
                          "oauth-openshift",
                          "console-openshift-console",
                          "grafana-openshift-monitoring",
                          "prometheus-k8s-openshift-monitoring",
                        ]
cluster_domain = "jupiter.example.com"
```
And the folder __Terraform/AppGateway__ contains:
```
$ ls -1 Terraform/AppGateway/
api-cert.pfx
api-root-CA.cer
AppGateway_input-vars.tf
AppGateway-main.tf
AppGateway_vars
apps-cert.pfx
apps-root-CA.cer
```
When the variables are defined and the certificate files are in place the Application Gateway can be deployed with the command:
```
$ terraform apply -var-file AppGateway_vars
```
The deployment will take a few minutes, but it could take a little longer to be operational until the health probes verify that the banckend pools can receive requests.

To access the cluster check the section [Accessing the Openshift Cluster through the Application Gateway](#accessing-the-openshift-cluster-through-the-application-gateway).

#### Obtaining the Certificate for API and Application Secure Routes
Connections to the API and the secure routes are encrypted end to end, from client to Openshift cluster.  The Application Gateway terminates all TLS connections and stablish new ones with the OCP cluster.  

To stablish the encrypted end to end connections for API and secure routes two certificates are required:
* **A PKCS12 (PFX) file**.- Contains the public and private parts of the certificate used to encrypt connections between clients and the application gateway.  

    The Application Gateway terminates the TLS connections so it needs a full certificate, containing the private and public keys.  

    This certificate can be obtained from a well known certification authority or generated internally.  This instructions show how to obtain and reuse these certificates by extracting them from the API endpoint and the default ingress controller, but a newly created certificate is also valid as long as it is a wildcard certificate.

    The certificate used to access application secure routes should be valid for the DNS domain of the applications, but the external and internal domains don't need to be the same, for example the external hostname of an application could be _app1.example.com_ and its internal name _app1.apps.ocp4.jupiter.net_, this provides a layer of abstraction that can hide the complexities of the OCP cluster behind the application gateway and can simplify the migration of applications from one cluster to another.  

    This repository only supports wildcard certificates, covering any application in the DNS domain for which the certificate is valid.  A wildcard certificate contains a CN field and possibly a SAN field like in the following example:

        Subject: CN = *.apps.jupiter.example.com
        ...
        X509v3 Subject Alternative Name: 
            DNS:*.apps.jupiter.example.com

    **The API endpoint certificate** components can be extracted by running the following command.  The command generates the files __tls.crt__ and __tls.key__.

        $ oc extract secret/external-loadbalancer-serving-certkey -n openshift-kube-apiserver
        tls.crt
        tls.key

    To build the PKCS12 (PFX) file required by the Application Gateway use the following command. The password requested by the command is used to encrypt the resulting _api-cert.pfx_ file, and must be assigned to the variable **api_cert_passwd**:

        $ openssl pkcs12 -export -out api-cert.pfx -inkey tls.key -in tls.crt
        Enter Export Password:
        Verifying - Enter Export Password:

    **The certificate for the secure routes** can be extracted running the following command, the __--confirm__ option is used to overwrite the files if they already exist.

        $ oc extract secret/router-certs-default -n openshift-ingress --confirm
        tls.crt
        tls.key

   To build the PKCS12 (PFX) file the following command is used, the password provided must be assigned to the variable **apps_cert_passwd**:

        $ openssl pkcs12 -export -out apps-cert.pfx -inkey tls.key -in tls.crt 
        Enter Export Password:
        Verifying - Enter Export Password:

   The terraform template expects to find the API endpoint PKCS12 certificate in a file called __api-cert.pfx__ and the PKCS12 certificate for application secure routes in a file called __apps-cert.pfx__, both in the directory __Terraform/AppGateway__.
   
* **An x509 certificate file**.- This file must contain the public part of the Certification Authority (CA) certificate used to sign the certificate served by the API endpoint and Openshift ingress controller respectively.  This certificate is used to verify the authenticity of the x509 certificate shown by the API endpoint and the ingress controller when an encrypted connection is stablished between the Application Gateway and the API endpoint or the ingress controller. 

    This certificate must be extracted from the OCP cluster.  In this instructions the _openssl_ tool will be used to obtain these certificates.

    **To obtain the CA certificate from the API endpoint** use a command like the following.  This certificate is not required if the API endpoint is not public.  Replace the cluster domain name in the example for that of the actual cluster.  The output contains, among other information, a certificate chain:

        $ echo |openssl s_client -showcerts -connect api.jupiter.example.com:6443
        ...
         1 s:OU = openshift, CN = kube-apiserver-lb-signer
           i:OU = openshift, CN = kube-apiserver-lb-signer
        -----BEGIN CERTIFICATE-----
        MIIDMjCCAhqgAwIBAgIISzOKW4LZ2kIwDQYJKoZIhvcNAQELBQAwNzESMBAGA1UE
        CxMJb3BlbnNoaWZ0MSEwHwYDVQQDExhrdWJlLWFwaXNlcnZlci1sYi1zaWduZXIw
        ...
        HYU2RTQxsBRlL016bi8q57oMn0S8/yMRYTRTu+CWQrZvI31+FaSBB2kvHoXvjtxm
        JtOIcSESjVbTWTeNwAj5BE9FHvH44FjsVb49kaLTj5bdsYMbrxaoW5IpPKIIHKyx
        8GJ8frRz
        -----END CERTIFICATE-----

    Copy the certificate prefixed with the **CN=kube-apiserver-lb-signer** and paste it into a file called **api-root-CA.cer**:

        $ echo "-----BEGIN CERTIFICATE-----
        > MIIDMjCCAhqgAwIBAgIISzOKW4LZ2kIwDQYJKoZIhvcNAQELBQAwNzESMBAGA1UE
        > CxMJb3BlbnNoaWZ0MSEwHwYDVQQDExhrdWJlLWFwaXNlcnZlci1sYi1zaWduZXIw
        ...
        > HYU2RTQxsBRlL016bi8q57oMn0S8/yMRYTRTu+CWQrZvI31+FaSBB2kvHoXvjtxm
        > JtOIcSESjVbTWTeNwAj5BE9FHvH44FjsVb49kaLTj5bdsYMbrxaoW5IpPKIIHKyx
        > 8GJ8frRz
        > -----END CERTIFICATE-----" > api-root-CA.cer

    The certificate file can be verified with the following command:

        $ openssl x509 -in api-root-CA.cer -text -noout

    **To obtain the CA certificate from the ingress controller** to be used for secure application routes use the following command.  This certicate is always required.  Replace the cluster domain name in the example for that of the actual cluster.

        $ echo |openssl s_client -showcerts -connect console-openshift-console.apps.jupiter.example.com:443
        ...
         1 s:CN = ingress-operator@1641392714
           i:CN = ingress-operator@1641392714
        -----BEGIN CERTIFICATE-----
        MIIDDDCCAfSgAwIBAgIBATANBgkqhkiG9w0BAQsFADAmMSQwIgYDVQQDDBtpbmdy
        ZXNzLW9wZXJhdG9yQDE2NDEzOTI3MTQwHhcNMjIwMTA1MTQyNTEzWhcNMjQwMTA1
        ...
        Zw4CXTUlIpqApGMF5YIn+3GX9t1+9fWIRjmz8P6p+9rw6o5IhAt5DnL9wFGf1qzD
        Zps4Hd8Evfl+byNHgijH2g==
        -----END CERTIFICATE-----

    Copy the certificate with **CN=ingress-operator@\<serial number\>** and paste it into a file called **apps-root-CA.cer**:

        $ echo "-----BEGIN CERTIFICATE-----
        MIIDDDCCAfSgAwIBAgIBATANBgkqhkiG9w0BAQsFADAmMSQwIgYDVQQDDBtpbmdy
        ZXNzLW9wZXJhdG9yQDE2NDEzOTI3MTQwHhcNMjIwMTA1MTQyNTEzWhcNMjQwMTA1
        ...
        Zw4CXTUlIpqApGMF5YIn+3GX9t1+9fWIRjmz8P6p+9rw6o5IhAt5DnL9wFGf1qzD
        Zps4Hd8Evfl+byNHgijH2g==
        -----END CERTIFICATE-----" > apps-root-CA.cer

    The certificate can be verified with the following command:

        $ openssl x509 -in apps-root-CA.cer -text -noout

The terraform template expects to find the CA cert for the API endpoint, if required, in a file called **api-root-CA.cer**, and the CA cert for the ingress controller in a file called **apps-root-CA.cer** in the directory __Terraform/AppGateway__.

### Accessing the Openshift Cluster through the Application Gateway
When the Application Gateway is deployed, the Openshift cluster can be accessed normally using the external DNS names that the certificates are valid for.  

For example if the API endpoint is public and the certificate is valid for the DNS name _api.jupiter.example.com_, the command to log into the cluster as the kubeadmin user would be:
```
$ oc login -u kubeadmin https://api.jupiter.example.com:6443
```
And if the wildcard certificate is valid for the domain _\*.apps.jupiter.example.com_ the cluster web console can be accessed at _https://console-openshift-console.apps.jupiter.example.com_

To be able to connect to these URLs and to the cluster in general, the DNS configuration in the client must be able to resolve the names _api.jupiter.example.com_ and any hostname associated with an application route in the domain _\*.apps.jupiter.example.com_.  

All these DNS records must resolve to the public IP of the Application Gateway, to find out the value of that IP run the following command in the directory __Terraform/AppGateway__:
```
$ terraform output frontend_pub_ip
"20.97.425.13"
```
A simple DNS configuration example using dnsmasq is shown in section [Configuring DNS resolution with dnsmasq](#configuring-dns-resolution-with-dnsmasq)

### Updating the Configuration
The Application Gateway configuration can be updated after deployment using the same terraform template that installs it.  Some examples that require updating the configuration are:
* Publishing or unpublishing the API endpoint
* Adding or removing new application routes
* Changing the PKCS12 or CA certificates

To update the configuration simply update the variables in the existing file, or create a new variables file, update the certificate files if needed, and run terraform command again:

```
$ terraform apply -var-file new_AppGateway_vars
```
Terraform will detect the changes and modify only the resources that are affected by these changes.

### Application Gateway Decommission
The terraform module for the Application Gateway is run independently from the one creating the infrastructure to deploy the Openshift cluster, that means the Application Gateway can be removed without affecting the rest of the infrastructure.

Removing the Application Gateway will have the effect of making the Openshift cluster private again, closing the access from the Internet to all published applications, using secure routes or not, and the API endpoint if this was published.

The command to remove the Application Gateway should be called passing the last variables definition file that was used to apply the configuration. 
```
$ terraform remove -var-file AppGateway_vars
```
If at a later time the Application gateway is created again using the same variables file, the resulting configuration should be the same except for the frontend public IP that will probably change.  In that case the DNS records resolving the external domain must be updated to use the new IP address.

## Configuring DNS resolution with dnsmasq
Here is how to setup dnsmasq in the client host to resolve the DNS queries for the API and application routes in the Openshift cluster.  The DNS records must resolve to the public IP addressof the Application Gateway, this IP can be found out by running the following command in the directory __Terraform/AppGateway__:
```
$ terraform output frontend_pub_ip
"20.97.425.13"
```
In this example dnsmasq is running as a NetworkManager plugging as is the case in Fedora and RHEL servers, if it was running as a standalone service the files are in /etc/dnsmasq.conf and /etc/dnsmasq.d/

To define dnsmasq as the default DNS server add a file to __/etc/NetworkManager/conf.d/__, any filename ending in .conf is good, with the contents:
```
[main]
dns=dnsmasq
```
Create a file in __/etc/NetworkManager/dnsmasq.d/__, again any filename ending in .conf is good.  This file contains the resolution records for the domain in question, the following example file contains two records:
* A type A record that resolves a single hostname into the IP address of the Application Gatewa
* A wildcard type A record that resolves a whole DNS domain into the IP address of the Application Gateway
```
host-record=api.jupiter.example.com,20.97.425.13
address=/.apps.jupiter.example.com/20.97.425.13
```
Now restart the NetworkManager service with:
```
$ sudo systemctl restart NetworkManager
```
The file /etc/resolv.conf should now contain a line pointing to 127.0.0.1 as the name server:
```
$ $ cat /etc/resolv.conf
# Generated by NetworkManager
...
nameserver 127.0.0.1
```
The resolution should be working now:
```
$ dig +short api.jupiter.example.com
20.97.425.13
```

## Publishing TLS Routes via the Application Gateway
@#Why is it necessary to specify every single route hostname instead of just using a default wildcard policy like in the case of the non secure applications#@
@#Why use a map instead of a set for hostname lists?  To avoid rebuilding a lot of the app gateway if the list is reordered alphabetically, and to allow defining different external and internal domains#@
@#Using let's encrypt to add a valid certificate to the Application Gateway#@
