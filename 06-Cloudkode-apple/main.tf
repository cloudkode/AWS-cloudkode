# Define VPC
resource "aws_vpc" "main" {
  cidr_block = "192.168.0.0/16"

  tags = {
    Name = "Cloudkode-vpc"
  }
}


# Define Subnets
resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "priv_subnet-1"
  }
}

resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "priv_subnet-2"
  }
}

resource "aws_subnet" "subnet3" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "pub_subnet-1"
  }
}

resource "aws_subnet" "subnet4" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.4.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "pub_subnet-2"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-gateway"
  }
}

resource "aws_eip" "nat_eip" {
  tags = {
    Name = "nat-eip"
  }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.subnet4.id

  tags = {
    Name = "nat-gateway"
  }
}

# Create Route Table
resource "aws_route_table" "public_RT" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public_RT"
  }
}

resource "aws_route_table" "private_RT" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private_RT"
  }
}

# Update Private Route Table to Route Traffic Through NAT Gateway
resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_RT.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}


# Associate Subnets with Route Tables
resource "aws_route_table_association" "subnet1_association" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.private_RT.id
}

resource "aws_route_table_association" "subnet2_association" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.private_RT.id
}

resource "aws_route_table_association" "subnet3_association" {
  subnet_id      = aws_subnet.subnet3.id
  route_table_id = aws_route_table.public_RT.id
}

resource "aws_route_table_association" "subnet4_association" {
  subnet_id      = aws_subnet.subnet4.id
  route_table_id = aws_route_table.public_RT.id
}

# Create Security Group
resource "aws_security_group" "HTTP-SG" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Add SSH ingress rule
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Replace with a more restrictive CIDR if needed
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "HTTP-SG"
  }
}

# Create Security Group
resource "aws_security_group" "jumper-SG" {
  vpc_id = aws_vpc.main.id

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

  tags = {
    Name = "jumper-SG"
  }
}

# Create S3 Bucket
resource "aws_s3_bucket" "Cloudkode_s3" {
  bucket = "cloudkode1-s3"
  force_destroy = true
  tags = {
    Name = "cloudkode1-s3"
  }
}

# Create IAM Role and Policy
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "s3_policy" {
  name   = "s3_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject"
        ],
        Effect   = "Allow",
        Resource = [
          "arn:aws:s3:::cloudkode1-s3",
          "arn:aws:s3:::cloudkode1-s3/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

# Attach IAM Role to EC2 Instances
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile"
  role = aws_iam_role.ec2_role.name
}

# Generate a new key pair for the jumper to access private instances
resource "tls_private_key" "jumper_to_private_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "jumper_to_private_key_pair" {
  key_name   = "jumper-to-private-key"
  public_key = tls_private_key.jumper_to_private_key.public_key_openssh
}

resource "aws_key_pair" "rizk" {
  key_name   = "rizk-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCd7Sg459Trr29W32e3JJMazfIKlUZM4WulaWLGvOKYLZHOlF2I8hdMBqobBaEnF8owqfhTX0wz9qF2zDiHouMcEfNHDjRkP6jZxWQrHKsuJzCoa6ImXWHiZw+3FbEEiJxbmWek2cL9eyAuA590KcOEspw023p4Pr6v/uGbGsPmmHnxsBDQGlDpsZSSLIa/TSo0/i3U0ze8gUTalgrVnt86A1TVsmtiqTFXxotmCvlPwbVaCK3qOt+MRY6bd49L0oY539XjnHkDWppVY3rwz4gyS9JGiPZYaMQCfigxQxskq3afZ9aHTbpsNRh0zbfiRjZa8r7d5S1su9lhd/SKNoMKHseD8QBqRBwmfnENe3SIkclQMAqcI1beMjcKN9BLlM0YFJxH/CHj31Mt5sniW3uctXxnI/6CHVXW6j518ihjVNxgfbSU6kYR9BLTzlu7EBdOesSzUrrRiDx163JYw+RlFYamupm8/Bs8+C1XbyYIvEuLH4NJSClBY146oqbHD/rF8iBV6VDyNLJ/NPa+ak/eGBRKFlovouKFh7g6tg5wFAA3cMJEp+y9EHWtXmFRra8iYmfLzPKzgjOkp1LswrxGp/oGPgmLm+2epca4bFhbIlh+sReFealB9yeIH1PiE+4ar8Tq4TQvHOJ0hzh47sfIaUbhhW6IG5MFZ9FcIIq3aw== any email"
}

# Create EC2 Instances
resource "aws_instance" "jumper_instance" {
  ami                         = "ami-0182f373e66f89c85"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.subnet3.id
  vpc_security_group_ids      = [aws_security_group.jumper-SG.id]
  associate_public_ip_address = true
  key_name = aws_key_pair.rizk.key_name

  user_data = <<-EOF
              #!/bin/bash
              mkdir -p /home/ec2-user/.ssh
              echo '${tls_private_key.jumper_to_private_key.private_key_pem}' > /home/ec2-user/.ssh/jumper_to_private_key.pem
              chmod 600 /home/ec2-user/.ssh/jumper_to_private_key.pem
              chown ec2-user:ec2-user /home/ec2-user/.ssh/jumper_to_private_key.pem
              EOF

  tags = {
    Name = "jump server"
  }

  depends_on = [aws_security_group.jumper-SG]
}

# Create Load Balancer (ALB)
resource "aws_lb" "test" {
  name               = "ALB-rizk"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.HTTP-SG.id]
  subnets            = [aws_subnet.subnet3.id, aws_subnet.subnet4.id]

  enable_deletion_protection = false

  tags = {
    Name = "Cloudkode-rizk"
  }
}

# Create Target Group
resource "aws_lb_target_group" "test" {
  name        = "TG-Cloudkode"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id

  health_check {
    protocol = "HTTP"
    path     = "/"
  }

  tags = {
    Name = "TG-cloudkode"
  }
}

# Create Listener for ALB
resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.test.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }
}


# Create Auto Scaling Group
resource "aws_launch_configuration" "app" {
  name          = "app-launch-configuration"
  image_id      = "ami-0182f373e66f89c85"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.jumper_to_private_key_pair.key_name
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  security_groups      = [aws_security_group.HTTP-SG.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y python3
              echo "Hello, World from ASG" > /home/ec2-user/index.html
              cd /home/ec2-user
              python3 -m http.server 80 &
              EOF
}

resource "aws_autoscaling_group" "app" {
  launch_configuration = aws_launch_configuration.app.id
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  vpc_zone_identifier  = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]

  target_group_arns = [aws_lb_target_group.test.arn]

  tag {
    key                 = "Name"
    value               = "ASG_Instance"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]  
  }
}