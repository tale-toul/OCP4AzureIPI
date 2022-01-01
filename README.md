#Openshift 4 on Azure on existing VNet using IPI installer 

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

Check for any updates in the terraform plugins:

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

#### Variables definition
Some of the resources created by terraform can be adjusted via the use of variables defined in the file Terrafomr/input-vars.tf:
* **region_name**.- Contains the name of the Azure region where the resources, and the Openshift cluster, will be created.
```
region_name: "France Central"
```
####Login to Azure
Before running terraform to create resources a user with enough permissions must be authenticated with Azure, there are several options to perform this authentication as explained in the [documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_certificate) for the Azure resource provider for terraform.  The simplest one is to use the Azure CLI to authenticate:

* Install __az__ [client](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli). On [RHEL]((https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=dnf#install))

* Login to azure with:
```  
$ az login
```  

#### Deploy infrastructure with Terraform
To create the infrastructure run the following commands.  Enter "yes" at the prompt:

```  
$ cd Terraform
$ terraform apply -var="region_name=West Europe"
...
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```  

