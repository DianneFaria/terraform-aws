provider "aws" {
  region = "us-east-1"
}

variable "projeto" {
  description = "Nome do projeto"
  type        = string
  default     = "vexpenses"
}

variable "candidato" {
  description = "Nome do candidato"
  type        = string
  default     = "dianne"
}

# Associar a chave privada ao EC2
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Definir par de chaves SSH
resource "aws_key_pair" "ec2_key_pair" {
  key_name   = "${var.projeto}-${var.candidato}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh

}

#Salvar a chave localmente
resource "local_file" "private_key_file" {
  filename        = "${path.module}/.ssh/${var.projeto}-${var.candidato}-key.pem"
  content         = tls_private_key.ec2_key.private_key_pem
  file_permission = "0400"
}

#Criar VPC
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.projeto}-${var.candidato}-vpc"
  }
}

#Criar subnets
resource "aws_subnet" "main_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${var.projeto}-${var.candidato}-subnet"
  }
}

#Subnet privado
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${var.projeto}-${var.candidato}-private-subnet"
  }
}

# Criar o segundo subnet publico para que seja usado pelo load balancer.
resource "aws_subnet" "main_second_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "${var.projeto}-${var.candidato}-subnet"
  }
}

# Criar internet gateway para acessar internet
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "${var.projeto}-${var.candidato}-igw"
  }
}

# Criar route table
resource "aws_route_table" "main_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-route_table"
  }
}

# Conectar o subnet publico a route table.
resource "aws_route_table_association" "main_association" {
  subnet_id      = aws_subnet.main_subnet.id
  route_table_id = aws_route_table.main_route_table.id
}

# Security group do EC2
resource "aws_security_group" "main_sg" {
  name        = "${var.projeto}-${var.candidato}-sg"
  description = "Permitir HTTP do ALB"
  vpc_id      = aws_vpc.main_vpc.id
  depends_on = [aws_security_group.alb_sg]

  ingress {
    description      = "Permitir trafego do SG do Load Balancer"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb_sg.id] 
  }

  # Regras de saída
  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-sg"
  }
}

# Criar Security Group do load balancer
resource "aws_security_group" "alb_sg" {
  name        = "${var.projeto}-${var.candidato}-alb-sg"
  description = "Permitir HTTP de qualquer lugar e todo o trafego de saida"
  vpc_id      = aws_vpc.main_vpc.id

# Regras de entrada
  ingress {
    description      = "Allow HTTP from anywhere"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

# Regras de saida
  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-alb-sg"
  }
}

# Criar o ALB
resource "aws_lb" "public_alb" {
  name               = "public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets           = [aws_subnet.main_subnet.id, aws_subnet.main_second_subnet.id]

  tags = {
    Name = "public-alb"
  }
}

# Definir qual porta o load balancer escuta
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.public_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_tg.arn
  }
}

# Criar o Target Group
resource "aws_lb_target_group" "main_tg" {
  name     = "tg-private-ec2"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id

  target_type = "instance"  

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }
}

# Associar a instancia ao target group
resource "aws_lb_target_group_attachment" "tg_attachment" {
  target_group_arn = aws_lb_target_group.main_tg.arn
  target_id        = aws_instance.debian_ec2.id
  port             = 80
}

#NAT GATEWAY - Para que o EC2 consiga acesar internet e baixar o ngnix
resource "aws_eip" "nat_eip" {}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.main_subnet.id  # Sub-rede pública

  tags = {
    Name = "${var.projeto}-${var.candidato}-nat-gateway"
  }
}

# Route table para ligar o subnet privado ao NAT gateway
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-private-route-table"
  }
}
resource "aws_route_table_association" "private_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

#Escolher a imagem Debian
data "aws_ami" "debian12" {
  most_recent = true

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["679593333241"]
}

# Criar EC2
resource "aws_instance" "debian_ec2" {
  ami             = data.aws_ami.debian12.id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.private_subnet.id
  key_name        = aws_key_pair.ec2_key_pair.key_name
  security_groups = [aws_security_group.main_sg.id]
  depends_on = [
    aws_vpc.main_vpc,
    aws_internet_gateway.main_igw,
    aws_nat_gateway.nat_gw,
    aws_subnet.private_subnet,
    aws_route_table_association.private_association,
    aws_security_group.main_sg,
    aws_lb.public_alb,
    aws_lb_listener.http
  ]
  associate_public_ip_address = false

  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = true
  }

  
# Atualizar o sistema, instalar nginx
  user_data = <<-EOF
                #!/bin/bash
                # O debian estava exibindo interface interativa para configurar o openssh-server
                echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections
                sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a
                # Atualizar pacotes e evitar prompts interativos
                sudo apt-get update -y
                sudo apt-get upgrade -y

                # Instalar pacotes adicionais
                sudo apt install -y nginx
              EOF

  tags = {
    Name = "${var.projeto}-${var.candidato}-ec2"
  }
}

output "ec2_public_ip" {
  description = "Endereço IP público da instância EC2"
  value       = aws_instance.debian_ec2.public_ip
}

output "alb_dns_name" {
  description = "Dominio publico do Load Balancer. Use para acessar o servidor"
  value       = aws_lb.public_alb.dns_name
}