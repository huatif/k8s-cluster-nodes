variable "region" {
  description = "AWS Region"
  default     = "ca-central-1"
}

variable "key_name" {
  description = "Existing AWS Key Pair Name"
  default     = "cks-learning"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.small"
}
