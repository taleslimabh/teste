resource "aws_security_group" "phoenix_sg" {
  name        = "phoenix_sg"
  description = "Security Group para aplicação Phoenix"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_instance" "phoenix_ec2" {
  ami           = "ami-0e83be366243f524a" # Ubuntu 22.04 us-east-2
  instance_type = "t3a.micro"
  subnet_id     = data.aws_subnets.default.ids[0]
  key_name      = var.key_name
  security_groups = [
    aws_security_group.phoenix_sg.id
  ]

  root_block_device {
    volume_size = 8
  }

  user_data = file("${path.module}/../user_data.sh")

  tags = {
    Name = var.instance_name
  }
}

resource "aws_s3_bucket" "phoenix_bucket" {
  bucket = var.bucket_name
}
