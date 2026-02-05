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
  default = "g4dn.xlarge"
}

variable "ami_name_prefix" {
  type    = string
  default = "pytorch-arc-eks-gpu"
}

variable "nvidia_driver_version" {
  type    = string
  default = "535.129.03"
}

# Get the latest Amazon EKS optimized GPU AMI
data "amazon-ami" "eks_gpu" {
  filters = {
    name                = "amazon-eks-gpu-node-1.29-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI account
  region      = var.region
}

source "amazon-ebs" "eks_gpu" {
  ami_name      = "${var.ami_name_prefix}-{{timestamp}}"
  instance_type = var.instance_type
  region        = var.region
  source_ami    = data.amazon-ami.eks_gpu.id
  ssh_username  = "ec2-user"

  tags = {
    Name        = "${var.ami_name_prefix}-{{timestamp}}"
    Environment = "shared"
    Project     = "pytorch-cloud"
    Type        = "eks-gpu"
  }

  launch_block_device_mappings {
    device_name = "/dev/xvda"
    volume_size = 200
    volume_type = "gp3"
    iops        = 3000
    throughput  = 125
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.eks_gpu"]

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

  # Verify NVIDIA drivers (should be pre-installed in EKS GPU AMI)
  provisioner "shell" {
    inline = [
      "nvidia-smi || echo 'NVIDIA drivers not found'",
    ]
  }

  # Install nvidia-docker2 (if not already installed)
  provisioner "shell" {
    inline = [
      "if ! command -v nvidia-container-runtime &> /dev/null; then",
      "  sudo yum install -y nvidia-docker2",
      "fi",
    ]
  }

  # Configure Docker with NVIDIA runtime
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/docker",
      "sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'",
      "{",
      "  \"default-runtime\": \"nvidia\",",
      "  \"runtimes\": {",
      "    \"nvidia\": {",
      "      \"path\": \"nvidia-container-runtime\",",
      "      \"runtimeArgs\": []",
      "    }",
      "  },",
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

  # Install ccache for build caching
  provisioner "shell" {
    inline = [
      "sudo yum install -y ccache",
      "sudo mkdir -p /var/cache/ccache",
      "sudo chmod 777 /var/cache/ccache",
    ]
  }

  # Install CUDA toolkit utilities
  provisioner "shell" {
    inline = [
      "sudo yum install -y cuda-toolkit-12-1 || echo 'CUDA toolkit already installed'",
    ]
  }

  # Install nvtop for GPU monitoring
  provisioner "shell" {
    inline = [
      "sudo yum install -y nvtop || echo 'nvtop not available in repos'",
    ]
  }

  # Enable GPU persistence mode
  provisioner "shell" {
    inline = [
      "sudo nvidia-smi -pm 1 || echo 'Could not set persistence mode'",
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

  # Verify GPU setup
  provisioner "shell" {
    inline = [
      "echo '=== GPU Verification ==='",
      "nvidia-smi",
      "docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi || echo 'Docker GPU test failed'",
    ]
  }
}
