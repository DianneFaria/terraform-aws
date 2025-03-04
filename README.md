# VExpenses

## Índice

- [Como inicializar e aplicar as configurações do Terraform no Windows](#como-inicializar-e-aplicar-as-configuracoes-do-terraform-no-windows)
- [Terraform arquivo original](#terraform-arquivo-original)
- [Terraform arquivo modificado](#terraform-arquivo-modificado)

## Como inicializar e aplicar as configurações do Terraform no Windows:

Pré-requisitos:
- Ter uma conta AWS
- Ter um usuário na conta da AWS (caso tenha algum problema com as permissões do usuário na hora de rodar a aplicação, basta dar a permissão "AmazonEC2FullAccess" ao usuário)
- Ter a AWS_ACCESS_KEY_ID e AWS_SECRET_ACCESS_KEY de seu usuário
- Instalar o Terraform e AWS CLI como mostra o passo a passo

Passo a passo:
- Abra seu terminal CMD
- Instalar Terraform ([Link para baixar Terraform](https://developer.hashicorp.com/terraform/install))
- Instalar AWS CLI ([Link para instalar AWS CLI](https://docs.aws.amazon.com/pt_br/cli/latest/userguide/getting-started-install.html))
- Configure as variáveis de ambiente: AWS_ACCESS_KEY_ID e AWS_SECRET_ACCESS_KEY do IAM AWS
- Criar uma pasta no diretório com → mkdir nome_da_pasta
- Acessar diretório criado com → cd nome_da_pasta
- Criar arquivo main.tf → echo. > main.tf
- Use o comando para abrir o notepad, cole o conteúdo do script e salve → notepad main.tf
- Usar comando inicializar → terraform init
- Usar comando para verificar formatação → terraform fmt
- Usar comando para validação sintática → terraform validate
- Usar comando para criar → terraform apply

# Terraform arquivo original

### Sugestões de melhoria

A instância EC2 está exposta na porta 22, qualquer IP pode tentar uma conexão. O ideal é que a instância que irá manter a aplicação fique em uma subnet privada, enquanto um proxy numa subnet pública, como um load balancer, trate de direcionar as chamadas para a aplicação. Para se conectar via SSH numa instância privada, uma boa sugestão é usar o serviço Systems Manager.

Para que a instância continue acessando a internet para baixar atualizações ou outros pacotes, poderíamos conectá-la a um NAT Gateway de uma subnet pública.

Também poderíamos passar a salvar a chave SSH localmente para que o output do Terraform não seja a única forma de consultar a chave. 

### Erros encontrados

1. **Erro na tag do recurso aws_route_table_association**
   
   Solução: Não usar tag neste recurso.
   
3. **Erro na descrição do ressarce aws_security_group**
   
   Solução:  Remover caracteres com acento.
    
6. **Erro: não encontrava o Security Group ao tentar associa-lo ao EC2**
   
   Solução: Mapear o SG por ID ao invés de nome.

### Rascunho do funcionamento original
<details>
  <summary>Ver imagem</summary>

  <img src="https://github.com/user-attachments/assets/417dfc5f-af13-45fd-b124-b09c6fdf3d5d" width="500"/>
  
</details>

## Descrição da configuração original

---

1. **Definir uma region para a estrutura, a us-east-1**
    
    ```
      provider "aws" {
      region = "us-east-1"
      }
    ```
    
2. **variáveis locais para guardar nome do projeto e do candidato**
    
    ```
      description = "Nome do projeto"
      type        = string
      default     = "VExpenses"
    }
    
    variable "candidato" {
      description = "Nome do candidato"
      type        = string
      default     = "SeuNome"
    }
    ```
    
3. **Criar um recurso AWS de par de chaves SSH**
   
    a. definindo o uso do algoritmo RSA 2048 com os parametros algorithm e rsa_bits
    
    ```
    resource "tls_private_key" "ec2_key" {
    algorithm = "RSA"
    rsa_bits  = 2048
    }
    ```
    
      b.  definindo um par de chaves, guardando a chave pública em public_key.
    
    ```
    resource "aws_key_pair" "ec2_key_pair" {
      key_name   = "${var.projeto}-${var.candidato}-key"
      public_key = tls_private_key.ec2_key.public_key_openssh
    }
    ```
    
      c. É possível referenciar as chaves pública e privada usando “public_key_openssh” e “private_key_pem” respectivamente.
    

## Configurar a rede: VPC, Subnet, IGW e Route Table

1. **Criando a nossa própria VPC, uma que não é pertencente a AWS.** 
    
    ```
      resource "aws_vpc" "main_vpc"
    ```
    
    a. Definir que essa VPC terá IP`s no intervalo de 10.0.0.0 a 10.0.255.255
        
    ```
      cidr_block           = "10.0.0.0/16"
    ```
        
    b. Definir suporte DNS para que a VPC use o servidor DNS da AWS para encontrar endereços públicos.
   
    ```
      enable_dns_support   = true
      enable_dns_hostnames = true
    ```
        
    c. O nome da VPC é VExpenses-dianne-vpc

    ```
      tags = {
      Name = "${var.projeto}-${var.candidato}-vpc"
    ```
        
3. **Criar a Subnet pública dentro da nossa VPC**
    
    ```
    resource "aws_subnet" "main_subnet" {
      vpc_id            = aws_vpc.main_vpc.id
     }
    ```
    
    a. É definido para ele um intervalo de IP`s de 10.0.1.0 a 10.0.1.255
        
     ```
       cidr_block        = "10.0.1.0/24"
     ```
        
    b. Definimos que ficará na availability zone us-east-1a
        
      ```
        availability_zone = "us-east-1a"
      ```
        
    c. O nome para a subnet é VExpenses-dianne-subnet

     ```
        tags = {
           Name = "${var.projeto}-${var.candidato}-subnet"
         }
      ```
        
5. **Criar o internet gateway da VPC para que recursos da subnet possam acessar a internet.** 
    
    ```
    resource "aws_internet_gateway" "main_igw" {
      vpc_id = aws_vpc.main_vpc.id
      }
    ```
    
    a. O nome para o IGW é VExpenses-dianne-igw

   ```
    tags = {
            Name = "${var.projeto}-${var.candidato}-igw"
          }
    ```
        
7. **Criar a route table na VPC para direcionar o tráfego da subnet para o internet gateway.**
    
    ```
    resource "aws_route_table" "main_route_table" {
      vpc_id = aws_vpc.main_vpc.id
      }
    ```
    
    a. A route table direciona todo o tráfego que recebe para VExpenses-dianne-igw
   
     ```
        route {
            cidr_block = "0.0.0.0/0"
            gateway_id = aws_internet_gateway.main_igw.id
          }
     ```
        
9. **Associar a subnet criada a route table, tornando-a pública.**
    
    a. A associação é feita através do subnet_id e route_table_id
    
    ```
    resource "aws_route_table_association" "main_association" {
      subnet_id      = aws_subnet.main_subnet.id
      route_table_id = aws_route_table.main_route_table.id
      }
    ```
    

## Definições para o EC2

1. **Criar um Security group na VPC para ser usado na EC2 que será criada.**
    
    ```
    resource "aws_security_group" "main_sg" {
      name        = "${var.projeto}-${var.candidato}-sg"
      description = "Permitir SSH de qualquer lugar e todo o tráfego de saída"
      vpc_id      = aws_vpc.main_vpc.id
      }
    ```
    
    a. O security group tem como regra de entrada permitir que qualquer IP se comunique com a porta 22. 
        
     ```
          # Regras de entrada
          ingress {
            description      = "Allow SSH from anywhere"
            from_port        = 22
            to_port          = 22
            protocol         = "tcp"
            cidr_blocks      = ["0.0.0.0/0"]
            ipv6_cidr_blocks = ["::/0"]
          }
     ```
        
    b. A regra de saída é permitir uso de qualquer porta, com qualquer protocolo, para qualquer ip.
        
     ```
          # Regras de saída
          egress {
            description      = "Allow all outbound traffic"
            from_port        = 0
            to_port          = 0
            protocol         = "-1"
            cidr_blocks      = ["0.0.0.0/0"]
            ipv6_cidr_blocks = ["::/0"]
          }
     ```
        
2. **Definir a  imagem AMI que será usada no SO da instância.**
    a. Definir um aws_ami, procurando sempre pela atualização mais recente e filtrando pelo nome debian-12-amd64-* do fornecedor “679593333241”
        
     ```
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
     ```
        
3. **Criar uma instância com a AMI definida, do tipo t2.micro. É o tipo de instância para uso geral, do tamanho micro.**
    
    ```
    resource "aws_instance" "debian_ec2" {
      ami             = data.aws_ami.debian12.id
      instance_type   = "t2.micro"
    }
    ```
    
    a. Especificar a qual subnet pertence, no caso, a subnet pública já criada.
        
     ```
          subnet_id       = aws_subnet.main_subnet.id
     ```
        
    b. Associar o par de chaves para ser usado na conexão SSH
        
     ```
          key_name        = aws_key_pair.ec2_key_pair.key_name
     ```
        
    c. Associar o Security Group que permite conexões SSH na porta 22.
        
     ```
          security_groups = [aws_security_group.main_sg.name]
     ```
        
    d.  Associar um endereço IP público para que seja possível se conectar ao EC2.
        
     ```
          associate_public_ip_address = true
     ```
        
    e. Volume do tipo uso geral, de 20GB, configurando para ser deletado quando a instância também for.
        
     ```
          root_block_device {
            volume_size           = 20
            volume_type           = "gp2"
            delete_on_termination = true
          }
     ```
        
    f. Adiciona um script em user_data que será executado uma vez quando a instância for criada. Ele vai atualizar o sistema com o apt-get
        
     ```
          user_data = <<-EOF
                      #!/bin/bash
                      apt-get update -y
                      apt-get upgrade -y
                      EOF
     ```
        

## Print da chave privada gerada e do ip público

```
output "private_key" {
  description = "Chave privada para acessar a instância EC2"
  value       = tls_private_key.ec2_key.private_key_pem
  sensitive   = true
}

output "ec2_public_ip" {
  description = "Endereço IP público da instância EC2"
  value       = aws_instance.debian_ec2.public_ip
}
```

# Terraform arquivo modificado

[Baixar o arquivo main.tf modificado](./main.tf)

## Objetivo

As modificações visaram colocar a instância em uma subnet privada afim de diminuir a exposição pública. O acesso passa a ser somente através do load balancer. Além de maior segurança, proporciona mais potencial de escala horizontal. 

Não foi implementado o acesso via SSH por Systems Manager, portanto, ainda não é possível acessar a instância diretamente.

## Changelog

- Criou uma subnet privada na VPC
- Criou um Application Load Balancer
- Criou um security group para o load balancer, para aceitar conexões na porta 80 somente.
- Criou uma segunda subnet pública para atender requisitos do ALB
- Modificou o Security group da instância para que aceite somente conexões na porta 80, vindas do load balancer
- Associou a instância a um Target group associado ao load balancer
- Criou um NAT Gateway na subnet pública para que o EC2 acesse a internet
- Alterou o user_data para instalar o nginx
- Removeu o print da chave privada no console; passou a salvar localmente em path.module/.ssh

### Rascunho do funcionamento modificado
<details>
  <summary>Ver imagem</summary>

  <img src="https://github.com/user-attachments/assets/78a73771-72ab-4fee-a44c-f7c567469e2e" width="500"/>
  
</details>

## Descrição da modificação

Descrição detalhada somente do que há de diferente em relação à primeira versão.

### Modificação nas chaves SSH

1. **Salvar localmente a chave privada**
    a. filename e content definem onde o arquivo será salvo. A permissão 0400 fará com que somente o dono do arquivo possa visualizar.
    
    ```
    resource "local_file" "private_key_file" {
      filename        = "${path.module}/.ssh/${var.projeto}-${var.candidato}-key.pem"
      content         = tls_private_key.ec2_key.private_key_pem
      file_permission = "0400"
    }
    ```
    

### Modificação na rede

**1. Criar uma subnet privada, ele irá conter a instância que roda o ngnix.**

```
resource "aws_subnet" "private_subnet" {}
```

a. Na private_subnet, definir um bloco de IP diferente da subnet pública já existente (a main_subnet)
    
    a subnet pública é definida com cidr_block = “10.0.1.0/24”, então agora definimos a subnet privada com cidr_block = “10.0.2.0/24”.
    
  ```
     cidr_block        = "10.0.2.0/24" # vai de 10.0.2.0 a 10.0.2.255
  ```
    
b. Definir a availability zone que a subnet privada pertencerá.
    
    Ela pertencerá a mesma AZ que a subnet pública já criada (a main_subnet).
    
  ```
      availability_zone = "us-east-1a"
  ```
    

**2. Criar uma segunda subnet pública, mas agora na AZ us-east-1b, pois os load balancers exigem no mínimo duas subnets públicas em duas AZ’s diferentes.**

Com a criação desta segunda, passaremos a ter publicamente as subnets main_subnet e main_second_subnet.

```
resource "aws_subnet" "main_second_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  **availability_zone = "us-east-1b" # aqui é definda uma AZ diferente.**

  tags = {
    Name = "${var.projeto}-${var.candidato}-subnet"
  }
}
```

**3. Criar um Security Group na VPC para o futuro Load Balancer**

```
resource "aws_security_group" "alb_sg" {}
```

a. Como regra de entrada, aceitar qualquer conexão, mas somente na porta 80
    
  ```
      ingress {
        description      = "Allow HTTP from anywhere"
        from_port        = 80
        to_port          = 80
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
      }
  ```
    
b. Na regra de saída, permitir usar qualquer porta, qualquer protocolo e direcionando para qualquer IP.
    
  ```
      egress {
        description      = "Allow all outbound traffic"
        from_port        = 0
        to_port          = 0
        protocol         = "-1"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
      }
  ```
    

**4. Alterar o security group usado pela instância, o SG main_sg, para que permita apenas conexão provinda do load balancer.** 

```
# aqui definimos que apenas o alb tem permissão para se conectar na instancia.
 security_groups  = [aws_security_group.alb_sg.id]
```

```
  ingress {
    description      = "Permitir trafego do SG do Load Balancer"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb_sg.id]
```

### Configuração de um Load Balancer

**1. Criação do Application load balancer**

a. Definir que ele é do tipo “application”. Também associá-lo ao security group já criado “alb_sg”

```
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
```

b. Esse trecho define que o alb pode usar as duas subnets públicas, que estão em diferentes AZ’s. Assim, duas AZ’s garantem mais disponibilidade do serviço ao usuário.

```
subnets           = [aws_subnet.main_subnet.id, aws_subnet.main_second_subnet.id]
```

c.  Criação do Target Group, isto é, para qual grupo de instâncias o ALB vai redirecionar o tráfego.

```
resource "aws_lb_target_group" "main_tg" {
  name     = "tg-private-ec2"
  port     = 80 # o target group escutará na porta 80 somente.
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
```

d.  Adicionar a nossa instância ao target group, “linkando” a instância ao target group criado.

```
resource "aws_lb_target_group_attachment" "tg_attachment" {
  target_group_arn = aws_lb_target_group.main_tg.arn
  target_id        = aws_instance.debian_ec2.id
  port             = 80 # todo tráfego do TG irá para a porta 80 da instancia.
}
```

### Configurar a **instância, agora dentro da subnet privada.**

**1. Criar um NAT Gateway dentro da subnet pública**

Esse NAT Gateway será usado para que nossa instância que fica na subnet privada consiga acessar a internet para baixar dependências, mantendo-se privada.

```
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.main_subnet.id  # Sub-rede pública

  tags = {
    Name = "${var.projeto}-${var.candidato}-nat-gateway"
  }
```

**2. Criar um NAT Gateway dentro da subnet pública**

Precisamos “linkar” a instância ao NAT Gateway que acabamos de criar. Usar uma route table para isso. Ao associar nossa instância a essa route table, todo tráfego da instância será enviado ao NAT Gateway.

a. Criando a route table que redireciona o tráfego recebido para o Nat Gateway.
    
  ```
    resource "aws_route_table" "private_route_table" {
      vpc_id = aws_vpc.main_vpc.id
    
      route {
        cidr_block = "0.0.0.0/0"
        **nat_gateway_id = aws_nat_gateway.nat_gw.id**
      }
    
      tags = {
        Name = "${var.projeto}-${var.candidato}-private-route-table"
      }
  ```
    
b. Agora, associar a instância a route table criada.
    
  ```
    resource "aws_route_table_association" "private_association" {
      subnet_id      = aws_subnet.private_subnet.id
      route_table_id = aws_route_table.private_route_table.id
    }
  ```
    

c. Nas configurações da instância,  adicionar o trecho depends_on para que a instãncia seja criada somente após todos esses recursos de rede serem criados.

```
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
```

d.  A instância não deve mais ter um ip público, pois agora ela está em uma subnet privada

```
  associate_public_ip_address = false
```

### Script de inicialização da instância
1. Tivemos que acrescentar também ao script, um trecho para impedir o Debian de exibir interface interativa para configurar o openssh-server, isso estava impedindo que o script rodasse por inteiro, então o ngnix não era instalado.
    
```
#!/bin/bash
# O debian estava exibindo interface interativa para configurar o openssh-server
echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selectionsudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a
```
    
2.  No script que roda ao inicializar uma nova instância, acrescentar a instalação do ngnix.

```
sudo apt install -y nginx
```
    

### Exibindo o DNS do ALB gerado

```
output "alb_dns_name" {
  description = "Dominio publico do Load Balancer. Use para acessar o servidor"
  value       = aws_lb.public_alb.dns_name
}
```
