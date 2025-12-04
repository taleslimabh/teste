variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "key_name" {
  description = "CHAVE SSH"
  type        = string
  default     = "my-test-key"
}

variable "instance_name" {
  description = "phoenix"
  type        = string
  default     = "project-phoenix-ec2"
}

variable "bucket_name" {
  description = "group-infra-selecao-taleslima.candidatoinfra1226"
  type        = string
  default     = "group-infra-selecao-taleslima.candidatoinfra1226"
}
