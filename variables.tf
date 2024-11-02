variable "db_user" {
  default = "postgres"
}

variable "db_password" {
  default = "password"
  sensitive   = true
}
