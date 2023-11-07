provider "aws" {
  region     = "eu-central-1"
  access_key = "AKIAVBZML7HLGQDQBZU6" 
  secret_key = "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"   
} 

 resource "aws_vpc" "cyberrange-vpc" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true
    tags = {
      name = "cyberrange vpc"
    }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cyberrange-vpc.id
  tags = {
    Name="internet gateway"
  }
}

resource "aws_route_table" "cyberrange_route" {
  vpc_id = aws_vpc.cyberrange-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "cyberrange_route"
  }
}

resource "aws_main_route_table_association" "cyberrange_route_association" {
  vpc_id = aws_vpc.cyberrange-vpc.id
  route_table_id = aws_route_table.cyberrange_route.id
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.cyberrange-vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "eu-central-1b"
  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.cyberrange-vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = false
  availability_zone = "eu-central-1b"

  tags = {
    Name = "private-subnet"
  }
}
 
// To Generate Private Key
resource "tls_private_key" "rsa_4096" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

variable "key_name" {
  description = "Name of the SSH key pair"
}

// Create Key Pair for Connecting EC2 via SSH
resource "aws_key_pair" "key_pair" {
  key_name   = var.key_name
  public_key = tls_private_key.rsa_4096.public_key_openssh
}

// Save PEM file locally
resource "local_file" "private_key" {
  content  = tls_private_key.rsa_4096.private_key_pem
  filename = var.key_name

  provisioner "local-exec" {
    command = "chmod 400 ${var.key_name}"
  }
}

resource "aws_security_group" "iptables-sg" {
  name        = "iptables security-groups"
  description = "Security group for iptables"
  vpc_id = aws_vpc.cyberrange-vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
      
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

   ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      aws_subnet.public_subnet.cidr_block,
    ]
  } 
  ingress {
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    from_port        = 5985
    to_port          = 5985
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = -1
    to_port          = -1
    protocol         = "icmp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
 variable "allowed_address" {
  description = "the allowed addresse"
} 

resource "aws_security_group" "private_security" {
depends_on = [ 
  aws_security_group.iptables-sg,
]
vpc_id = aws_vpc.cyberrange-vpc.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.iptables-sg.id]
  }

   ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [var.allowed_address]
  } 
  
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "all"
    cidr_blocks = ["0.0.0.0/0"]
  }

  
}

 resource "aws_instance" "iptables_instance" {
  depends_on = [ 
   aws_security_group.iptables-sg,
   ]
  ami = "ami-04e601abe3e1a910f"
  instance_type = "t3.nano"
  key_name = aws_key_pair.key_pair.key_name
  subnet_id = aws_subnet.public_subnet.id
  private_ip = "10.0.1.10"
  availability_zone = "eu-central-1b"
  vpc_security_group_ids = [ aws_security_group.iptables-sg.id ]
  source_dest_check           = false


    /* user_data = <<-EOT
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y iptables
              sudo iptables -F
              sudo iptables --table nat --append POSTROUTING --out-interface ens5 -j MASQUERADE
              sudo iptables --append FORWARD --in-interface ens6 -j ACCEPT
              sudo echo 1 > /proc/sys/net/ipv4/ip_forward
              service iptables restart
              EOT */

  tags = {
    Name = "iptables_instance"
  }
}

resource "aws_network_interface" "ens6" {
  subnet_id       = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.private_security.id,
  ]
  
  tags = {
    Name = "elastic_network_interface"
  }
}

resource "aws_network_interface_attachment" "iptables_ens6" {
    instance_id = aws_instance.iptables_instance.id
    network_interface_id = aws_network_interface.ens6.id
    device_index = 1
  }


resource "null_resource" "configure_ens6"{
  depends_on = [ 
    aws_network_interface_attachment.iptables_ens6,
    aws_security_group.private_security,
  ]

  connection {
    type  = "ssh"
    user  = "ubuntu"
    private_key = file("${var.key_name}")   
    host        = aws_instance.iptables_instance.public_ip
  }

  provisioner "remote-exec"{
    inline = ["sudo apt install net-tools",
      "sudo ifconfig ens6 up",
    ]
  }
}

 resource "aws_instance" "windows_instance" {
  depends_on = [
    aws_security_group.private_security,
  ]

  ami           = "ami-09e36f47f07100bdb"
  instance_type = "t2.large"
  subnet_id     = aws_subnet.private_subnet.id
  private_ip = "10.0.2.20"

  vpc_security_group_ids = [aws_security_group.private_security.id]

  key_name               = aws_key_pair.key_pair.key_name

  associate_public_ip_address = true

  user_data         = base64encode(templatefile("${path.module}/install_ftp.tpl", {})) 
  tags = {
    Name = "windows_instance"
  }
}

  resource "aws_instance" "app_instance" {
  depends_on = [ 
    aws_security_group.private_security, ]

  ami                    = "ami-02480f5d9eb21a996"
  instance_type          = "t2.large"
  availability_zone = "eu-central-1b"
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.private_security.id]
  subnet_id = aws_subnet.private_subnet.id
  private_ip = "10.0.2.10"

  tags = {
    Name = "app_instance"
  }
  associate_public_ip_address = true
}

data "template_file" "inventory" {
  template = <<-EOT
    [app_instance]
    ${aws_instance.app_instance.public_ip} ansible_user=ubuntu ansible_private_key_file=${path.module}/${var.key_name}
    EOT
}

resource "local_file" "dynamic_inventory" {
  depends_on = [aws_instance.app_instance]

  filename = "dynamic_inventory.ini"
  content  = data.template_file.inventory.rendered

  provisioner "local-exec" {
    command = "chmod 400 ${local_file.dynamic_inventory.filename}"
  }
}

resource "null_resource" "run_ansible" {
  depends_on = [local_file.dynamic_inventory]

  provisioner "local-exec" {
    command     = "ansible-playbook -i dynamic_inventory.ini app.yml"
    working_dir = path.module
  }
}

 output "iptables_instance_private_ip" {
  value = aws_instance.iptables_instance.private_ip
}

output "second_iptables_interface_private_ip" {
  value = aws_network_interface.ens6.private_ip
}

  output "app_instance_private_ip" {
  value = aws_instance.app_instance.private_ip
} 
output "windows_instance_private_ip" {
  value = aws_instance.windows_instance.private_ip
}
