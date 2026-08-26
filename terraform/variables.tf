variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
  
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "kind"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone" {
    description = "Availability zone for the VPC"
    type        = string
    default     = "us-east-1a"
  
}

variable "vpc_name" {
  description = "Name prefix for VPC resources"
  type        = string
  default     = "task-api-vpc"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes in the EKS node group"
  type        = number
  default     = 3  
}

variable "node_min_size" {
  description = "Minimum number of worker nodes in the EKS node group"
  type        = number
  default     = 1  
}

variable "node_max_size" {
  description = "Maximum number of worker nodes in the EKS node group"
  type        = number
  default     = 3  
}
