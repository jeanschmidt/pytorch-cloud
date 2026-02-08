variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-1"
}

variable "base_node_count" {
  description = "Number of base infrastructure nodes (fixed size)"
  type        = number
  default     = 5
}

variable "base_node_instance_type" {
  description = "Instance type for base infrastructure nodes"
  type        = string
  default     = "m5.xlarge"
}

variable "base_node_max_unavailable_percentage" {
  description = "Maximum percentage of base nodes to update simultaneously"
  type        = number
  default     = 100 # Staging: Replace all nodes immediately for fast updates
}
