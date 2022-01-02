# Openshift 4 on Azure on existing VNet using IPI installer 

## Introduction

The instructions and code in this repository can be used to deploy an Openshift 4 cluster in Azure on a existing VNet using the IPI installer.  
The OCP cluster can be [public](https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-vnet.html) or [private.](https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-private.html)

## Cluster deployment

The deployment process consists of the following points:

* [Create the infrastructure components in Azure](#create-the-infrastructure-with-terraform).- The VNet and other components are created using terraform
* [Set up installation environment].- 
* [Run the Openshift installer]

### Create the infrastructure with Terraform
Terraform is used to create the network infrastructure resources to deploy the Openshift cluster into.  The [terraform Azure provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) is used.  

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

#### Login to Azure
Before running terraform to create resources a user with enough permissions must be authenticated with Azure, there are several options to perform this authentication as explained in the [documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_certificate) for the Azure resource provider for terraform.  The simplest one is to use the Azure CLI to authenticate:

* Install __az__ [client](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli). On [RHEL]((https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=dnf#install))

* Login to azure with:
```  
$ az login
```  
Once successfully loged in, the file ~/.azure/azureProfile.json is created containing credentials that are used by the az CLI and terraform to run commands in Azure.  This credentials are valid for the following days so no further authentication with Azure is required for a while.

#### Variables definition
Some of the resources created by terraform can be adjusted via the use of variables defined in the file Terrafomr/input-vars.tf:
* **region_name**.- Contains the name of the Azure region where the resources, and the Openshift cluster, will be created.
```
region_name: "France Central"
```
* **create_bastion**.- Boolean used to determine if the bastion infrastructure will be created or not (defaults to true, the bastion will be created).
```
create_bastion: false
```
#### SSH key
If the bastion infrastructure is going to be created ([Conditionally creating the bastion infrastructure](#conditionally-creating-the-bastion-infrastructure)), an ssh key is needed to connect to the bastion VM, password authentication is disabled in the virtual machine.

Terraform expects a file containing the public ssh key in a file at __Terraform/Bastion/ocp-install.pub__.  This can be an already existing ssh key or a new one can be [created](https://docs.openshift.com/container-platform/4.9/installing/installing_azure/installing-azure-private.html#ssh-agent-using_installing-azure-private):

```
$ ssh-keygen -o -t rsa -f ocp-install -N "" -b 4096
```
The previous command will generate two files: ocp-install containing the private key and ocp-install.pub containing the public key.  The private key is not protected y a passphrase.

#### Deploy infrastructure with Terraform
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
Save the command used to create the infrastructure for future reference

```  
$ echo "!!" > terraform_apply.txt
```  
## Bastion infrastructure
Reference documentation on how to create the VM with terraform in Azure [1](https://docs.microsoft.com/en-us/azure/developer/terraform/create-linux-virtual-machine-with-infrastructure) and [2](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine)
A bastion host is deployed in its own subnet and gets assigned a network security rule that allows ssh connections into it.  The bastion host is intended to run the OCP 4 installer from it.

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

### Destroying the bastion infrastructure
The bastion infrastructure is created by an independent module so it can be destroyed without affecting the rest of the resources.  This is usefull to reduce costs and unneeded resources once the Openshift cluster has been deployed.

The command to destroy only the bastion infrastructure is:
```
$ terraform destroy -target module.bastion
```
__WARNING__ If the __-target__ option is not used, terraform will delete all resources.

The option `-target module.<name>` is used to affect only a particular module in the terraform command
