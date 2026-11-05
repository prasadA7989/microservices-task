
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "microdev"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "allowed_ssh_cidr" {
  description = "Approved public IP address for SSH"
  type        = string
}

variable "allowed_http_cidr" {
  description = "Approved public IP address for HTTP"
  type        = string
}

variable "public_key_path" {
  description = "Path to the EC2 SSH public key"
  type        = string
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 25
}
