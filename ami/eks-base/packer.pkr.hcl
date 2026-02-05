packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "instance_type" {
  type    = string
  default = "m5.large"
}

variable "ami_name_prefix" {
  type    = string
  default = "pytorch-arc-eks-base"
}

# Get the latest Amazon EKS optimized AMI
data "amazon-ami" "eks" {
  filters = {
    name                = "amazon-eks-node-1.29-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI account
  region      = var.region
}

source "amazon-ebs" "eks_base" {
  ami_name      = "${var.ami_name_prefix}-{{timestamp}}"
  instance_type = var.instance_type
  region        = var.region
  source_ami    = data.amazon-ami.eks.id
  ssh_username  = "ec2-user"

  tags = {
    Name        = "${var.ami_name_prefix}-{{timestamp}}"
    Environment = "shared"
    Project     = "pytorch-cloud"
    Type        = "eks-base"
  }

  launch_block_device_mappings {
    device_name = "/dev/xvda"
    volume_size = 100
    volume_type = "gp3"
    iops        = 3000
    throughput  = 125
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.eks_base"]

  # Update system packages
  provisioner "shell" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y amazon-ssm-agent",
      "sudo systemctl enable amazon-ssm-agent",
    ]
  }

  # Install development tools
  provisioner "shell" {
    inline = [
      "sudo yum groupinstall -y 'Development Tools'",
      "sudo yum install -y htop iotop sysstat vim wget curl git jq",
    ]
  }

  # Install ccache for build caching
  provisioner "shell" {
    inline = [
      "sudo yum install -y ccache",
      "sudo mkdir -p /var/cache/ccache",
      "sudo chmod 777 /var/cache/ccache",
    ]
  }

  # Configure Docker
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/docker",
      "sudo tee /etc/docker/daemon.json > /dev/null <<EOF",
      "{",
      "  \"log-driver\": \"json-file\",",
      "  \"log-opts\": {",
      "    \"max-size\": \"10m\",",
      "    \"max-file\": \"3\"",
      "  },",
      "  \"storage-driver\": \"overlay2\",",
      "  \"mtu\": 1500",
      "}",
      "EOF",
    ]
  }

  # Cleanup
  provisioner "shell" {
    inline = [
      "sudo yum clean all",
      "sudo rm -rf /var/cache/yum",
      "sudo rm -rf /tmp/*",
    ]
  }
}
