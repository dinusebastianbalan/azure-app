#############################################################################
# DATA
#############################################################################

data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

#############################################################################
# VARIABLES
#############################################################################

variable "resource_group_name" {
  type        = string
  default     = "demo_air"
  description = "Main infrastructure resource group name"
}

variable "location" {
  type        = string
  default     = "centralus"
  description = "Default location"
}


variable "vnet_cidr_range" {
  type        = string
  default     = "192.168.0.0/16"
  description = "Main Virtual Network CIDR"
}

variable "subnet_prefixes" {
  type        = list(string)
  default     = ["192.168.100.0/24", "192.168.220.0/24"]
  description = "Subnets CIDR for demo,AppGW"
}


variable "subnet_names" {
  type        = list(string)
  default     = [ "AksdemoSubnet" ,"AppGwdemoSubnet"]
  description = "Subnet names for demo,AppGW"
}


variable "aks_demo_rg_name" {
  type        = string
  default     = "demo_air_rg"
  description = "AKS demo resource group name"
}

variable "aks_prefix_demo" {
  type        = string
  default     = "demoair"
  description = "AKS demo prefix naming"
}

variable "ACR_name" {
  type        = string
  default     = "demoairACR"
  description = "Azure Container Registry name"
}

variable "sp_client_id" {
  type        = string
  default     = "14100345-27c4-489a-9fd6-97598d675648"
  description = "Client_id for Service Principal"
}

variable "sp_secret" {
  type        = string
  default     = "qurJ16rWiEIO17OH2t.mHCZ.t31K~-tBmA"
  description = "Secret for Service Principal"
}

variable "appgw_ip_name" {
  type        = string
  default     = "demoair_publicIP1"
  description = "name of the AppGw PublicIP"
}

variable "public_ip_domain_name" {
  type        = string
  default     = "demoairpublic"
}

variable "identity_rg" {
  type        = string
  default     = "demo_air_rg"
}

variable "AkvIdentity-demo" {
  type        = string
  default     = "aksidentity"
}

variable "key_vault_demo_name" {
  type        = string
  default     = "keyvault-demo-air"
}

#############################################################################
# PROVIDERS
#############################################################################

provider "azurerm" {
  version = "~> 2.34.0"
  features {
    }
}


#############################################################################
# RESOURCES
#############################################################################



## Virtual Network & Subnets ##
## .terraform/modules/vnet-main/main.tf

module "vnet-main" {
  source              = "Azure/vnet/azurerm"
  version             = "1.2.0"
  resource_group_name = var.resource_group_name
  location            = var.location
  vnet_name           = var.resource_group_name
  address_space       = var.vnet_cidr_range
  subnet_prefixes     = var.subnet_prefixes
  subnet_names        = var.subnet_names

  tags = {
    environment = "Infrastructure"

  }
}

data "azurerm_subnet" "aksdemosubnet" {
  name                 = var.subnet_names[0]
  virtual_network_name = var.resource_group_name
  resource_group_name  = var.resource_group_name

  depends_on          = [module.vnet-main]
}


data "azurerm_subnet" "aksappgwsubnet" {
  name                 = var.subnet_names[1]
  virtual_network_name = var.resource_group_name
  resource_group_name  = var.resource_group_name

  depends_on          = [module.vnet-main]
}

## demo AKS cluster ##
## .terraform/modules/aks-demo/main.tf

resource "azurerm_resource_group" "maindemo" {
  name     = var.aks_demo_rg_name
  location = var.location
}

module "aks-demo" {
  source              = "Azure/aks/azurerm"
  resource_group_name = azurerm_resource_group.maindemo.name
  client_id           = var.sp_client_id
  client_secret       = var.sp_secret
  prefix              = var.aks_prefix_demo
  
  depends_on          = [azurerm_resource_group.maindemo]


}

# azurerm_key_vault.Akvdemo:
resource "azurerm_key_vault" "keyvaultdemo" {
    enabled_for_deployment          = false
    enabled_for_disk_encryption     = false
    enabled_for_template_deployment = false
    location                        = var.location
    name                            = var.key_vault_demo_name
    sku_name                        = "standard"
    purge_protection_enabled        = false
    resource_group_name             = azurerm_resource_group.maindemo.name
    tenant_id                       = data.azurerm_client_config.current.tenant_id
    soft_delete_enabled             = false
    tags                            = {}

    network_acls {
        bypass                     = "AzureServices"
        default_action             = "Allow"
        ip_rules                   = []
        virtual_network_subnet_ids = []
    }

    timeouts {}
}

data "azurerm_user_assigned_identity" "AkvIdentity_demo" {
  name                 = var.AkvIdentity-demo
  resource_group_name  = var.identity_rg
}



## Azure Container Regestry ##

resource "azurerm_container_registry" "acr" {
  name                     = var.ACR_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = "Standard"
  admin_enabled            = false
}



# azurerm_public_ip.publicIP:
resource "azurerm_public_ip" "publicIP" {
    allocation_method       = "Static"
    domain_name_label       = var.public_ip_domain_name
    ip_version              = "IPv4"
    location                = var.location
    name                    = var.appgw_ip_name
    resource_group_name     = var.resource_group_name
    sku                     = "Standard"
    tags                    = {}
    zones                   = []

    timeouts {}

    depends_on          = [module.vnet-main]
}

##Application Gatewaty

locals {
  beap_demo  = "cluster-demo"
  be_affinity_cookie_name  = "ApplicationGatewayAffinity"
  be_cookie_based_affinity  = "Disabled"
  be_http_name  = "appGatewayBackendHttpSettings"
  be_http_protocol  = "Http"
  fe_ip_name  = "appGatewayFrontendIP"
  fe_ip_allocation  = "Dynamic"
  fe_port_http_name  = "appGatewayFrontendPort"
  fqdn  = "demoairpublic.centralus.cloudapp.azure.com"
  redirect_type  = "Permanent"
  rule_type  = "Basic"
  http_listener_demo  = "cluster-demo-http"
  redirect_configuration_demo_80  = "cluster-demo-80"
  redirect_configuration_demo_80_test  = "cluster-demo-80_test"
  http_listener_name_demo  = "cluster-demo-http"
  appgw_sku_name  = "WAF_v2"
  appgw_sku_tier  = "WAF_v2"
  waf_config_fw  = "Prevention"
  waf_config_rule_type  = "OWASP"
  waf_config_rule_version   = "3.1"
  cookie_based_affinity  = "Disabled"
}

resource "azurerm_application_gateway" "appgw-demo" {
    enable_http2        = false
    location            = var.location
    name                = var.public_ip_domain_name
    resource_group_name = var.resource_group_name
    tags                = {}
    zones               = []

    backend_address_pool {
        ip_addresses = [
            "192.168.100.240",
        ]
        name         = local.beap_demo
    }

    backend_http_settings {
        affinity_cookie_name                = local.be_affinity_cookie_name
        cookie_based_affinity               = "Disabled"
        name                                = local.be_http_name
        pick_host_name_from_backend_address = false
        port                                = 80
        protocol                            = "Http"
        request_timeout                     = 30
        trusted_root_certificate_names      = []

        connection_draining {
            drain_timeout_sec = 1
            enabled           = false
        }
    }

    frontend_ip_configuration {
        name                          = local.fe_ip_name
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.publicIP.id
    }

    frontend_port {
        name = local.fe_port_http_name
        port = 80
    }


    gateway_ip_configuration {
        name      = local.fe_ip_name
        subnet_id = data.azurerm_subnet.aksappgwsubnet.id
    }

    http_listener {
        frontend_ip_configuration_name = local.fe_ip_name
        frontend_port_name             = local.fe_port_http_name
        host_name                      = local.fqdn
        host_names                     = []
        name                           = local.http_listener_name_demo
        protocol                       = local.be_http_protocol
        require_sni                    = false
    }

    request_routing_rule {
        http_listener_name          = local.http_listener_name_demo
        name                        = local.redirect_configuration_demo_80
        backend_address_pool_name   = local.beap_demo
        backend_http_settings_name  = local.be_http_name
        rule_type                   = local.rule_type
    }

    sku {
        capacity = 1
        name     = local.appgw_sku_name
        tier     = local.appgw_sku_tier
    }

    firewall_policy_id = azurerm_web_application_firewall_policy.waf-policy.id

    timeouts {}

    depends_on          = [azurerm_resource_group.maindemo]

}

# azurerm_web_application_firewall_policy.waf-policy:
resource "azurerm_web_application_firewall_policy" "waf-policy" {
    location            = var.location
    name                = "waf-policy-demo"
    resource_group_name = var.resource_group_name
    tags                = {}

    custom_rules {
        action    = "Allow"
        name      = "grafana-rule"
        priority  = 1
        rule_type = "MatchRule"

        match_conditions {
            match_values       = [
                "/grafana",
            ]
            negation_condition = false
            operator           = "Contains"
            transforms         = [
                "Lowercase",
            ]

            match_variables {
                variable_name = "RequestUri"
            }
        }
    }

    managed_rules {
        exclusion {
            match_variable          = "RequestArgNames"
            selector                = "logContent"
            selector_match_operator = "Contains"
        }

        managed_rule_set {
            type    = "OWASP"
            version = "3.1"
        }
    }

    policy_settings {
        enabled                     = true
        file_upload_limit_in_mb     = 100
        max_request_body_size_in_kb = 128
        mode                        = "Prevention"
        request_body_check          = true
    }

    timeouts {}

    depends_on          = [azurerm_resource_group.maindemo]
}

#############################################################################
# OUTPUTS
#############################################################################

output "vnet_id" {
  value = module.vnet-main.vnet_id
}

output "subnet_id_demo" {
  value = data.azurerm_subnet.aksdemosubnet.id
}

output "subnet_id_appgw" {
  value = data.azurerm_subnet.aksappgwsubnet.id
}