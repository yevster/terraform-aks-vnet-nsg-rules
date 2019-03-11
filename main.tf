resource "azurerm_resource_group" "k8s" {
    name     = "${var.resource_group_name}"
    location = "${var.location}"
}

resource "azurerm_network_security_group" "onprem-nsg" {
    name                = "jbhunt-nsg"
    location            = "${azurerm_resource_group.k8s.location}"
    resource_group_name = "${azurerm_resource_group.k8s.name}"

    security_rule {
        name                       = "SSH"
        priority                   = 400
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
       source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "MasterNodeInbound443"
        priority                   = 401
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "443"
       source_address_prefix      = "*"
        destination_address_prefix = "VirtualNetwork"
    }


    security_rule {
        name                       = "WorkerNodeTCPInbound10250"
        priority                   = 402
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "10250"
       source_address_prefix      = "*"
        destination_address_prefix = "VirtualNetwork"
    }


    security_rule {
        name                       = "WNodeExternalAppConsumers"
        priority                   = 403
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "30000-32767"
        source_address_prefix      = "*"
        destination_address_prefix = "VirtualNetwork"
    }
    
     security_rule {
        name                       = "InterClusterCommunication"
        priority                   = 404
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*" // Allow both TCP and UDP
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "VirtualNetwork"
    }

    security_rule {
        name                       = "EtcdInboundMasterNode"
        priority                   = 405
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "2379-2380"
       source_address_prefix      = "*"
        destination_address_prefix = "VirtualNetwork"
    }


// This rule should be covered by VNET to VNET rule InterClusterCommunication
    security_rule {
        name                       = "EtcdInboundWorkerNode"
        priority                   = 406
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "2379-2380"
       source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "VirtualNetwork"
    }

    tags {
        environment = "onprem"
    }
}

resource "azurerm_subnet_network_security_group_association" "mgmt-nsg-association" {
  subnet_id                 = "${data.azurerm_subnet.kubesubnet.id}"
  network_security_group_id = "${azurerm_network_security_group.onprem-nsg.id}"
}

resource "azurerm_virtual_network" "test" {
   name                = "${var.virtual_network_name}"
   location            = "${azurerm_resource_group.k8s.location}"
   resource_group_name = "${azurerm_resource_group.k8s.name}"
   address_space       = ["${var.virtual_network_address_prefix}"]

   subnet {
     name           = "${var.aks_subnet_name}"
     address_prefix = "${var.aks_subnet_address_prefix}" 
   }
}

 data "azurerm_subnet" "kubesubnet" {
   name                 = "${var.aks_subnet_name}"
   virtual_network_name = "${azurerm_virtual_network.test.name}"
   resource_group_name  = "${azurerm_resource_group.k8s.name}"
 }


resource "azurerm_kubernetes_cluster" "k8s" {
    name                = "${var.cluster_name}-2"
    location            = "${azurerm_resource_group.k8s.location}"
    resource_group_name = "${azurerm_resource_group.k8s.name}"
    dns_prefix          = "${var.dns_prefix}"

    linux_profile {
        admin_username = "ubuntu"

        ssh_key {
            key_data = "${file("${var.ssh_public_key}")}"
        }
    }

    agent_pool_profile {
        name            = "agentpool"
        count           = "${var.agent_count}"
        vm_size         = "Standard_DS1_v2"
        os_type         = "Linux"
        os_disk_size_gb = 30
        vnet_subnet_id  = "${data.azurerm_subnet.kubesubnet.id}"
    }

    service_principal {
        client_id     = "${var.client_id}"
        client_secret = "${var.client_secret}"
    }


network_profile {
    network_plugin     = "azure"
    dns_service_ip     = "${var.aks_dns_service_ip}"
    docker_bridge_cidr = "${var.aks_docker_bridge_cidr}"
    service_cidr       = "${var.aks_service_cidr}"
  }

    tags {
        Environment = "Development"
    }
} 