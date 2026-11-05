
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_key_pair" "deploy_key" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.public_key_path))

  tags = {
    Project = var.project_name
  }
}

resource "aws_security_group" "app_sg" {
  name_prefix = "${var.project_name}-sg-"
  description = "Security group for microservices"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.app_sg.id

  cidr_ipv4   = var.allowed_ssh_cidr
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"

  description = "SSH from approved IP"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.app_sg.id

  cidr_ipv4   = var.allowed_http_cidr
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  description = "HTTP from approved IP"
}

resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.app_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  description = "Outbound package and registry access"
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_ecr_repository" "services" {
  for_each = toset([
    "user",
    "product",
    "order"
  ])

  name                 = "${var.project_name}-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
    Service = each.key
  }
}

resource "aws_instance" "application" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  subnet_id              = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  key_name                    = aws_key_pair.deploy_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name    = "${var.project_name}-application"
    Project = var.project_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecr_read
  ]
}
