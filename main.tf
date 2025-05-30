# main.tf

provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket         = "my-oidc-bucket-15328069840"
    key            = "alb-path-routing/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = { Name = "main-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "main-igw" }
}

resource "aws_subnet" "subnet_a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "subnet-a" }
}

resource "aws_subnet" "subnet_b" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "subnet-b" }
}

resource "aws_subnet" "subnet_c" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1c"
  tags = { Name = "subnet-c" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "c" {
  subnet_id      = aws_subnet.subnet_c.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "allow_http_ssh" {
  name        = "allow_http_ssh"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "instance_a" {
  ami           = var.ami
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet_a.id
  vpc_security_group_ids = [aws_security_group.allow_http_ssh.id]
  key_name      = var.key_name

  tags = { Name = "Instance A" }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y nginx
              sudo systemctl start nginx
              echo '<h1>Home page!</h1>' > /var/www/html/index.html
              EOF
}

resource "aws_instance" "instance_b" {
  ami           = var.ami
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet_b.id
  vpc_security_group_ids = [aws_security_group.allow_http_ssh.id]
  key_name      = var.key_name

  tags = { Name = "Instance B" }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y nginx
              sudo systemctl start nginx
              echo '<h1>Images!</h1>' > /var/www/html/index.html
              EOF
}

resource "aws_instance" "instance_c" {
  ami           = var.ami
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet_c.id
  vpc_security_group_ids = [aws_security_group.allow_http_ssh.id]
  key_name      = var.key_name

  tags = { Name = "Instance C" }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y nginx
              sudo systemctl start nginx
              echo '<h1>Register!</h1>' > /var/www/html/index.html
              EOF
}

resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http_ssh.id]
  subnets            = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id, aws_subnet.subnet_c.id]
}

resource "aws_lb_target_group" "tg_a" {
  name     = "tg-a"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group" "tg_b" {
  name     = "tg-b"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group" "tg_c" {
  name     = "tg-c"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group_attachment" "a" {
  target_group_arn = aws_lb_target_group.tg_a.arn
  target_id        = aws_instance.instance_a.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "b" {
  target_group_arn = aws_lb_target_group.tg_b.arn
  target_id        = aws_instance.instance_b.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "c" {
  target_group_arn = aws_lb_target_group.tg_c.arn
  target_id        = aws_instance.instance_c.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_a.arn
  }
}

resource "aws_lb_listener_rule" "images" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_b.arn
  }

  condition {
    path_pattern {
      values = ["/images*"]
    }
  }
}

resource "aws_lb_listener_rule" "register" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_c.arn
  }

  condition {
    path_pattern {
      values = ["/register*"]
    }
  }
}

# variables.tf
variable "ami" {
  default = "ami-0af9569868786b23a" # Ubuntu (example)
}

