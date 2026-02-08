variable "aws_region" {
  description = "AWS region for production environment"
  type        = string
  default     = "us-west-2"
}

variable "base_node_count" {
  description = "Number of base infrastructure nodes"
  type        = number
  default     = 5
}

variable "base_node_instance_type" {
  description = "Instance type for base infrastructure nodes"
  type        = string
  default     = "t3.large"
}

variable "base_node_max_unavailable_percentage" {
  description = "Maximum percentage of base nodes to update simultaneously"
  type        = number
  default     = 33 # Production: Conservative rolling updates (1 of 3 nodes)
}
