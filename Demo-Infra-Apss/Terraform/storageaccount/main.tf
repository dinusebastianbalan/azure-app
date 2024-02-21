#############################################################################
# VARIABLES
#############################################################################

variable "naming_prefix" {
  type    = string
  default = "demoair"
}

#############################################################################
# PROVIDERS
#############################################################################

provider "azurerm" {
  version = "~> 2.22.0"
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

## Storage account ##


resource "azurerm_resource_group" "storageaccount" {
  name     = "storage"
  location = "westeurope"
}

resource "random_integer" "sa_num" {
  min = 10000
  max = 99999
}

resource "azurerm_storage_account" "sa" {
  name                     = "${lower(var.naming_prefix)}${random_integer.sa_num.result}"
  resource_group_name      = azurerm_resource_group.storageaccount.name
  location                 = azurerm_resource_group.storageaccount.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

}

resource "azurerm_storage_container" "ct" {
  name                 = "terraform-state"
  storage_account_name = azurerm_storage_account.sa.name
}

data "azurerm_storage_account_sas" "state" {
  connection_string = azurerm_storage_account.sa.primary_connection_string
  https_only        = true

  resource_types {
    service   = true
    container = true
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = timestamp()
  expiry = timeadd(timestamp(), "17520h")

  permissions {
   read    = true
   write   = true
   delete  = true
   list    = true
   add     = true
   create  = true
   update  = false
   process = false
  }
}

#############################################################################
# PROVISIONERS
#############################################################################

resource "null_resource" "post-config" {

  depends_on = [azurerm_storage_container.ct]

  provisioner "local-exec" {
    command = <<EOT
echo 'storage_account_name = "${azurerm_storage_account.sa.name}"' >> backend-config.txt
echo 'container_name = "terraform-state"' >> backend-config.txt
echo 'key = "terraform.tfstate"' >> backend-config.txt
echo 'sas_token = "${data.azurerm_storage_account_sas.state.sas}"' >> backend-config.txt
EOT
  }
}

#############################################################################
# OUTPUTS
#############################################################################

output "storage_account_name" {
  value = azurerm_storage_account.sa.name
}

