variable "db_user" {
  default = "postgres"
}

variable "db_password" {
  sensitive   = true
}
