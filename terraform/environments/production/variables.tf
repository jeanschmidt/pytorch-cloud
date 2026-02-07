variable "aws_region" {
  description = "AWS region for production environment"
  type        = string
  default     = "us-west-2"
}

variable "base_node_count" {
  description = "Number of base infrastructure nodes"
  type        = number
  default     = 3 # HA for production
}

variable "base_node_instance_type" {
  description = "Instance type for base infrastructure nodes"
  type        = string
  default     = "t3.large"
}
