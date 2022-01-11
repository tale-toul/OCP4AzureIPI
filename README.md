# Openshift 4 on Azure on existing VNet using IPI installer 

## Table of Contents
* [Introduction](#introduction)
* [Outbound traffic configuration](#outbound-traffic-configuration)
* [Cluster deployment](#cluster-deployment)
  * [Create the infrastructure with Terraform](#create-the-infrastructure-with-terraform)
    * [Terraform installation](#terraform-installation)
    * [Terraform initialization](#terraform-initialization)
    * [Login into Azure](#login-into-azure)
    * [Variables definition](#variables-definition)
    * [SSH key](#ssh-key)
    * [Deploy the infrastructure with Terraform](#deploy-the-infrastructure-with-terraform)
* [Bastion infrastructure](#bastion-infrastructure)
  * [Conditionally creating the bastion infrastructure](#conditionally-creating-the-bastion-infrastructure)
  * [Destroying the bastion infrastructure](#destroying-the-bastion-infrastructure)
* [Set up the bastion host to install Openshift](#set-up-the-bastion-host-to-install-openshift)
* [OCP Cluster Deployment](#ocp-cluster-deployment)
* [Cluster decommissioning instructions](#cluster-decommissioning-instructions)
* [Accessing the OpenShift Cluster from The Internet](#accessing-the-openshift-cluster-from-the-internet)

## Introduction

The instructions and code in this repository can be used as an example to deploy an Openshift 4 cluster using the IPI installer in Azure on an existing VNet.  The VNet and related Azure resources required to deploy the OCP cluster are created using terraform. 
The OCP cluster can be [public](https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-vnet.html), that is accessible from Intenet; or [private.](https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-private.html) only accessible from the VNet where it is deployed.

The Azure resources required to deploy the Openshift 4 cluster is an existing VNet are:
* Resource Group.- That contains the following resources
* VNet
* Subnets.- Two subnets are needed, one for the control plane (masters) and one for the worker nodes.
* Network security groups.- One for each of the above subnets with its own security rules.
* Resources and configuration for the oubound network traffic from the cluster nodes to the Internet.- The requirement for these resources depends on the value of the variable [outboundType](#outbound-traffic-configuration) in the install-config.yaml file.

These resources are usually created by the IPI installer, to let it know that they already exist and should not be created during cluster intallation the following variables must be defined in the __platform.azure__ section in the install-config.yaml file:

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
## Outbound traffic configuration
The network resources and configuration allowing the cluster nodes to connect to the Internet (outbound traffic) depend on the value of the variable __outboundType__ in the install-config.yaml file. This configuration is independent from that of the inbound cluster traffic, whether this is a public or private cluster.

The __outboundType__ variable can take only two possible values: Loadbalancer and UserDefinedRouting:
* **LoadBalancer**.- The IPI installer will create an outbound rule in the public load balancer to allow outgoing connections from the nodes to the Internet.  If the the cluster is public, the load balancer is used for routing both inbound traffic from the Internet to the nodes and outbound traffic from the nodes to the Internet.  If the cluster is private there is no inbound traffic from the Internet to the nodes, but the load balancer will still be created and will only be used for outbound traffic from the nodes to the Internet.
* **UserDefinedRouting**.- The necessary infrastructure and configuration to allow the cluster nodes to connect to the internet must be in place before running the IPI installer, different options exit in Azure for this: NAT gateway; Azure firewall; Proxy server; etc.  In this repository the terraform template creates a NAT gateway if the **outbound_type** variable contains the value _UserDefinedRouting_.  

When outboundType = UserDefinedRouting, a load balancer is still created but contains no frontend IP address, load balancing rules or outbound rules, so it serves no purpose.  A fully functional internal load balancer is always created for access to the API service and applications only from inside the VNet.

## Cluster deployment

The deployment process consists of the following points:

* [Create the infrastructure components in Azure](#create-the-infrastructure-with-terraform).- The VNet and other components are created using terraform.
* [Set up installation environment](#set-up-the-bastion-host-to-install-openshift).- The bastion host is prepared to lauch the openshift installer from it.
* [Run the Openshift installer](#ocp-cluster-deployment)

### Create the infrastructure with Terraform
Terraform is used to create in Azure the network infrastructure resources required to deploy the Openshift 4 cluster into.  The [terraform Azure provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) is used.  

#### Terraform installation

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
Before running terraform to create resources a user with enough permissions must be authenticated with Azure, there are several options to perform this authentication as explained in the terraform [documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_certificate) for the Azure resource provider.  The simplest authentication method uses the Azure CLI:

* Install __az__ [client](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli). On [RHEL]((https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=dnf#install))

* Login to azure with:
```  
$ az login
```  
Once successfully loged in, the file __~/.azure/azureProfile.json__ is created containing credentials that are used by the az CLI and terraform to run commands in Azure.  This credentials are valid for the following days so no further authentication with Azure is required for a while.

#### Variables definition
Some of the resources created by terraform can be adjusted via the use of variables defined in the file Terrafomr/input-vars.tf:
* **region_name**.- Contains the short name of the Azure region where the resources, and the Openshift cluster, will be created. The short name of the regions can be obtained from the __Name__ column in the output of the command `az account list-locations -o table`
```
region_name: "francecentral"
```
* **create_bastion**.- Boolean used to determine if the bastion infrastructure will be created or not (defaults to true, the bastion will be created).
```
create_bastion: false
```
**cluster_scope**.- Used to define if the cluster will be public (accessible from the Internet) or private (not accessible from the Internet).  Can contain only two values: "public" or "private", default is public
```
cluster_scope: public
```
**outbound_type**.- Defines the networking method that cluster nodes use to connect to the Internet (outbound traffic).  Can have the values: _LoadBalancer_, the installer will create a load balancer with outbound rules, even if the cluster scope is private; and _UserDefinedRouting_, the outbound rules in the load balancer will not be created and the user must provide the outbound configuration, for example a NAT gateway".  Defaults to _LoadBalancer_.
```
outbound_type: LoadBalancer
```

#### SSH key
Regardless of whether the the bastion infrastructure is going to be created ([Conditionally creating the bastion infrastructure](#conditionally-creating-the-bastion-infrastructure)), an ssh key is needed to connect to the bastion VM and the OCP cluster nodes.

Terraform expects a file containing the public ssh key in a file at __Terraform/Bastion/ocp-install.pub__.  This can be an already existing ssh key or a new one can be [created](https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-private.html#ssh-agent-using_installing-azure-private):

```
$ ssh-keygen -o -t rsa -f ocp-install -N "" -b 4096
```
The previous command will generate two files: ocp-install containing the private key and ocp-install.pub containing the public key.  The private key is not protected y a passphrase.

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
Reference documentation on how to create the VM with terraform in Azure [1](https://docs.microsoft.com/en-us/azure/developer/terraform/create-linux-virtual-machine-with-infrastructure) and [2](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine)

By default a bastion host is created in its own subnet and gets assigned a network security rule that allows ssh connections into it.  The bastion host is intended to run the OCP 4 installer from it, and once the OCP cluster is installed, it can be used to access the cluster using the __oc__ cli.

The bastion infrastructure is created from a module in terraform so it can be conditionally created and easily destroyed once it is not needed anymore.

The bastion VM gets both public and private IP addresses assigned to the single NIC that it gets.  The network security group is directly associated with the NIC.

The disk image used is the latest version of a RHEL 8.  The same definition can be used irrespective of the region where the resources will be deployed.  The az cli commands used to collect the information for the definition can be found [here](https://docs.microsoft.com/en-us/cli/azure/vm/image?view=azure-cli-latest), for example:

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

## Set up the bastion host to install Openshift
Ansible is used to prepare the bastion host so the Openshift 4 cluster installation can be run from it.  Before running the playbook some prerequisites must be fullfilled:

Define the following variables in the file __Ansible/group_vars/all/cluster-vars__:
* Cluster name.- A unique name for the Openshift cluster, assign the name to the variable **cluster_name**. 
```
cluster_name: jupiter
```
* DNS base domain.- This domain is used to access the Openshift cluster and the applications running in it.  In the case of a public cluster, this DNS domain must exist in an Azure resource group before the cluser can be deployed.  In the case of a private cluster, a private domain will be created, there is no need to own that domain since it will only exist in the private VNet where the cluster is deployed.  The full domain is built as __<cluster name>.<>base domain>__, so for example if cluster name is __jupiter__ and base domain is __example.com__ the full cluster DNS domain is __jupiter.example.com__.  Assing the domain name to the variable **base_domain**.
```
base_domain: example.com
```
* Base domain resource group.- The Azure resource group name where the base domain exists.  Assing the name to the variable **base_domain_resource_group**
```
base_domain_resource_group: waawk-dns
```
* Number of compute nodes.- The number of compute nodes that the installer will create. Assing the number to the variable **compute_replicas**.
```
compute_replicas: 3
```
Download the Pull secret, Openshift installer and oc cli from [here](https://cloud.redhat.com/openshift/install), uncompress the installer and oc cli, and copy all these files to __Ansible/ocp_files/__

The inventory file for ansible containing the [bastion] group is created by the ansible playbook itself so there is no need to create this file.

The same ssh public key used for the bastion host is the one to be injected to the Openshift cluster nodes, so here again there is no need to provide a specific one.

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
jupiter/  oc*  openshift-install*
```
The directory contains the configuration file __install-config.yaml__, review and modify the file as required.

Before running the installer it is a good practice to backup the install-config.yaml because the installer removes it as part of the installation process, and also run the installer in a tmux session so the terminal doesn't get blocked for around 40 minutes, which is the time the installation needs to complete.

```
$ cp jupiter/install-config.yaml .
$ tmux
```
Run the Openshift installer, it will prompt for the Azure credentials requires to create all resources, after that the installer starts creating the cluster components:
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

## Cluster decommissioning instructions
Deleting the cluster is a two step process:

* Delete the components created by the openshift-install binary, run this command from the same directory in which the installation was run, if the bastion host has been previously deleted, recover a backup from the OCP4 directory:
```
$ ./openshift-install destroy cluster --dir jupiter
```
* Delete the components created by terraform, use the terraform destroy command with the same variable definitions that were used when the resources were created. This command should be run from the same directory from which the terraform apply command was run:
```
$ cd Terraform
$ terraform destroy -var region_name="germanywestcentral" -var cluster_scope="private"
```

## Accessing a private OpenShift Cluster from The Internet
If the Openshift cluster deployed following the instructions in this repository is private, the API and any application deployed in it are not accessible from the Internet.  This may be the desired state when the cluster is deployed, but at a later time when the cluster is fully set up and production applications are deployed and ready, it is possible that a particular set of applications or even the API are expected to be publicly available.  

There are many options to make applications and API publicly available, this repository includes a terraform module that can be used for such purpose, it can be found in the directory __Terraform/AppGateway__.  This module creates an [application gateway](https://docs.microsoft.com/en-us/azure/application-gateway/) that provides access to the applications running in the cluster and optionally to the API endpoint.

To successfully deploy the Application Gateway, the Azure infrastructure must have been deployed using the terraform templates in this repository, and the Openshift cluster needs to be already running.

### Variables definition
The following variables are used to pass information to terraform so the Application Gateway can be created and configured, some of these variables are used to adjust the configuration.  Add the variables definition to a file in the __Terraform/AppGateway__ directory, for example **AppGateway_vars** and call it in with the option **-var-file AppGateway_vars**:

The next two variables can be obtained from the Azure portal or using the following commands:

Get the list of load balancers in the resource group created by the IPI installer.  The LB with the _internal_ word in its name is the one of interest here, the other LB is not even functional in a private cluster:
```
$ az network lb list -g lana-l855j-rg -o table
Location            Name                 ProvisioningState    ResourceGroup    ResourceGuid
------------------  -------------------  -------------------  ---------------  ------------------------------------
germanywestcentral  lana-l855j           Succeeded            lana-l855j-rg    73c41f07-886c-46f1-b4cc-007b64924ff4
germanywestcentral  lana-l855j-internal  Succeeded            lana-l855j-rg    9a4d37c9-b139-479b-9905-e12743a3ac47
```
Get the frontend IPs associated with the internal LB, the one with the name _internal-lb-ip-v4_ is the IP for the API endpoint, the one with the long string of random characters is the IP for application access:
```
$ az network lb frontend-ip list -g lana-l855j-rg --lb-name lana-l855j-internal -o table
Name                              PrivateIpAddress    PrivateIpAddressVersion    PrivateIpAllocationMethod    ProvisioningState    ResourceGroup
--------------------------------  ------------------  -------------------------  ---------------------------  -------------------  ---------------
internal-lb-ip-v4                 10.0.1.4            IPv4                       Dynamic                      Succeeded            lana-l855j-rg
a0a66b12128ec4f33bbf3fb705e48e9e  10.0.2.8            IPv4                       Dynamic                      Succeeded            lana-l855j-rg
```
Further details for the IPs can be obtained by using a command like:
```
$ az network lb frontend-ip show -g lana-l855j-rg --lb-name lana-l855j-internal -n internal-lb-ip-v4|jq
```

* **api_lb_ip**.- Private IP of the internal load balancer used for API access.  This variable is not required if the API endpoint is not going to be made public.
```
api_lb_ip = "10.0.1.4"
```
* **apps_lb_ip**.- Private IP of the internal load balancer used for application access.  This variable is always required.
```
apps_lb_ip = "10.0.2.8"
```
* **api_cert_passwd**.- Password to decrypt PKCS12 certificate for API listener. This variable is not required if the API endpoint is not going to be made public.
```
api_cert_passwd = "avmapu"
```
* **apps_cert_passwd**.- Password to decrypt PKCS12 certificate for APPS listener. This variable is always required.
```
apps_cert_passwd = "avmapu"
```
* **ssl_listener_hostnames**.- List of valid hostnames for the listener and http settings used to access applications in the \*.apps domain when using TLS connections.  This variable is always required.
```
ssl_listener_hostnames = [ "httpd-example-caprice", 
                          "oauth-openshift",
                          "console-openshift-console",
                          "grafana-openshift-monitoring",
                          "prometheus-k8s-openshift-monitoring",
                        ]
```
* **cluster_domain**.- DNS domain used by cluster. This variable is always required.
```
cluster_domain = "lana.azurecluster.sureshot.pw"
```
* **publish_api**.- This boolean variable determines if the API entry point is to be published.  Defaults to false or the API endpoint will not be made public.
```
publish_api = true
```
