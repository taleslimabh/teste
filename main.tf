# AWS
# terraform {
#  required_providers {
#    aws = {
#      source  = "hashicorp/aws"
#      version = "~> 5.0"
#    }
#  }

#  backend "s3" {
#    bucket = "group-infra-selecao-taleslima.candidatoinfra1226"
#    key    = "terraform/phoenix.tfstate"
#    region = "us-east-2"
#  }
# }


# FIZ teste local

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
