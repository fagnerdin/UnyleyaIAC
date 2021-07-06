# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.65.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "fagnercorrea" {
  name     = "fagner-vmres"
  location = "West Europe"
}

# VIRTUAL NETWORK
resource "azurerm_virtual_network" "fagnervirnet" {
  name                = "fgVnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.fagnercorrea.location
  resource_group_name = azurerm_resource_group.fagnercorrea.name

  tags = {
    environment = "Unyleya"
  }
}

# SUBNET
resource "azurerm_subnet" "fagnersubnet" {
  name                 = "fagnerSubnet"
  resource_group_name  = azurerm_resource_group.fagnercorrea.name
  virtual_network_name = azurerm_virtual_network.fagnervirnet.name
  address_prefix       = "10.0.1.0/24"
}

# Create public IPs
resource "azurerm_public_ip" "fagnerpip" {
  name                = "FagPubIP"
  resource_group_name = azurerm_resource_group.fagnercorrea.name
  location            = azurerm_resource_group.fagnercorrea.location
  allocation_method   = "Static"

  tags = {
    environment = "Unyleya"
  }
}

# NETWORK SECURITY GROUP AND RULE 
resource "azurerm_network_security_group" "fagnernsgr" {
  name                = "FagnerNetSecGroup"
  location            = azurerm_resource_group.fagnercorrea.location
  resource_group_name = azurerm_resource_group.fagnercorrea.name


  security_rule {
    name                       = "RDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "WinRM"
    priority                   = 998
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "tcp"
    source_port_range          = "*"
    destination_port_range     = "5986"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }


  tags = {
    environment = "Unyleya"
  }
}

# Create network interface
resource "azurerm_network_interface" "nicfagner" {
  name                = "FagnerNIC"
  location            = azurerm_resource_group.fagnercorrea.location
  resource_group_name = azurerm_resource_group.fagnercorrea.name

  ip_configuration {
    name                          = "FagnerNicConfig"
    subnet_id                     = azurerm_subnet.fagnersubnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.fagnerpip.id
  }

  tags = {
    environment = "Unyleya"
  }
}

# adiciona chave dessa maquina da azure
resource "azurerm_ssh_public_key" "fagnerssh" {
  name                = "fagner-vm-ssh"
  resource_group_name = azurerm_resource_group.fagnercorrea.name
  location            = azurerm_resource_group.fagnercorrea.location
  public_key          = file("~/.ssh/id_rsa.pub")
}

resource "tls_private_key" "sshfagner" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

output "tls_private_key" {
  value     = tls_private_key.sshfagner.private_key_pem
  sensitive = true
}

# Create virtual machine
resource "azurerm_virtual_machine" "fagnercorreavm" {
  name                  = "VMFagner"
  location              = azurerm_resource_group.fagnercorrea.location
  resource_group_name   = azurerm_resource_group.fagnercorrea.name
  network_interface_ids = ["${azurerm_network_interface.nicfagner.id}"]
  vm_size               = "Standard_A4_v2"

  storage_os_disk {
    name              = "fagnerOsDisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    offer     = "WindowsServer"
    publisher = "MicrosoftWindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  os_profile {
    computer_name  = "ativiunyleya"
    admin_username = "fagnercorrea"
    admin_password = "F@gn3r-Unyleya!"
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = false
  }

  tags = {
    environment = "Unyleya"
  }
}

resource "azurerm_virtual_machine_extension" "instalassh" {
  name                 = "ssh-fg-unyleya"
  virtual_machine_id   = azurerm_virtual_machine.fagnercorreavm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  settings = <<SETTINGS
    {
        "commandToExecute": "powershell -command Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0",
        "commandToExecute": "powershell -command Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0",
        "commandToExecute": "powershell -command Start-Service sshd",
        "commandToExecute": "powershell -command Set-Service -Name sshd -StartupType 'Automatic'",
        "commandToExecute": "powershell -command Get-NetFirewallRule -Name *ssh*",
        "commandToExecute": "powershell -command New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22"
    }
SETTINGS

  tags = {
    environment = "Unyleya"
  }
}
