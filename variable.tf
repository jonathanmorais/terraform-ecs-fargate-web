variable "cluster" {
  type        = string
  description = "ECS Cluster name"
}

variable "application" {
  type = object({
    name        = string
    version     = string
    environment = string
  })
}

variable "container" {
  type = object({
    image                             = string
    cpu                               = string
    memory                            = string
    port                              = string
    health_check_grace_period_seconds = number
  })

}

variable "scale" {
  type = object({
    min = string
    max = string
    cpu = string
  })
}


variable "environment" {
  type    = list(map(string))
  default = []
}

variable "command" {
  type    = list(string)
  default = []
}

variable "network" {
  type = object({
    vpc             = string
    subnets         = list(string)
    security_groups = list(string)
  })
}

variable "service_policy" {
  type        = string
  description = "Policy to be attached on service execution role"
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags to assign to the resource."
}

locals {
  service_id = "${var.application.name}-${var.application.version}-${var.application.environment}"
}

variable "capacity_provider" {
  type = string
}

variable "tg" {
  type = object({
    deregistration_delay             = number
    health_check_path                = string
    health_check_healthy_threshold   = number
    health_check_unhealthy_threshold = number
    health_check_timeout             = number
    interval                         = number
  })

  default = {
    deregistration_delay             = 300
    health_check_path                = "/"
    health_check_healthy_threshold   = 5
    health_check_unhealthy_threshold = 2
    health_check_timeout             = 5
    interval                         = 30
  }
}

variable "alb" {
  type = object({
    enable                     = bool
    public                     = bool
    subnets                    = list(string)
    enable_deletion_protection = bool
    security_groups            = list(string)
    certificate_domain         = string
    idle_timeout               = number
    redirect_to_https          = bool

  })

  default = {
    enable                     = false
    public                     = false
    subnets                    = []
    enable_deletion_protection = true
    security_groups            = []
    certificate_domain         = ""
    idle_timeout               = 0
    redirect_to_https          = true
  }
}
