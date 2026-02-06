variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-1"
}

variable "base_node_count" {
  description = "Number of base infrastructure nodes (fixed size)"
  type        = number
  default     = 10
}

variable "base_node_instance_type" {
  description = "Instance type for base infrastructure nodes"
  type        = string
  default     = "m5.xlarge"
}
