variable "prod_username" {
  description = "Production Database administrator username"
  type        = string
  sensitive   = true
}

variable "prod_password" {
  description = "Production Database administrator password"
  type        = string
  sensitive   = true
}

variable "dr_username" {
  description = "Disaster Recovery Database administrator username"
  type        = string
  sensitive   = true
}

variable "dr_password" {
  description = "Disaster Recovery Database administrator password"
  type        = string
  sensitive   = true
}
