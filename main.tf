terraform {
  required_providers {
    aws = {
      version = ">= 2.7.0"
      source = "hashicorp/aws"
    }
  }
  backend "remote" {
    # The name of Terraform Cloud organization.
    organization = "example-org-28b01e"
    # The name of the Terraform Cloud workspace to store Terraform state files in.
    workspaces {
      name = "api-lambda-postgres"
        }
    }
}

provider "aws" {
  region = "ap-southeast-2"
}

resource "aws_db_instance" "postgres" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "16.4"
  instance_class       = "db.t3.micro"
  db_name              = "mydb"
  username             = var.db_user
  password             = var.db_password
  skip_final_snapshot  = true

  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  lifecycle {
    ignore_changes = [password]
  }
}

resource "aws_security_group" "rds_sg" {
  name = "allow-postgres"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lambda_function" "app" {
  filename         = "${path.module}/lambda/handler.zip"  # Zip containing handler.py
  function_name    = "app_lambda"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.8"

  environment {
    variables = {
      DB_HOST     = aws_db_instance.postgres.address
      DB_NAME     = "mydb"
      DB_USER     = var.db_user
      DB_PASSWORD = var.db_password
    }
  }
}

resource "aws_lambda_function" "authorizer" {
  filename         = "${path.module}/lambda/authorizer.zip"  # Zip containing authorizer.py
  function_name    = "authorizer_lambda"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "authorizer.lambda_handler"
  runtime          = "python3.8"
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name = "serverless-api"
}

resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "users"
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.auth.id
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.auth.id
}

resource "aws_api_gateway_authorizer" "auth" {
  name                   = "lambda-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api.id
  authorizer_uri         = aws_lambda_function.authorizer.invoke_arn
  identity_source        = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 300
}

resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_method.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.app.invoke_arn
  depends_on = [
    aws_api_gateway_method.post_method
  ]

}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.get_method.http_method
  type        = "AWS_PROXY"
  integration_http_method = "GET"
  uri         = aws_lambda_function.app.invoke_arn
  depends_on = [
    aws_api_gateway_method.get_method
  ]

}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
  depends_on  = [
    aws_api_gateway_method.get_method,
    aws_api_gateway_method.post_method,
    aws_api_gateway_integration.get_integration,
    aws_api_gateway_integration.post_integration
  ]
}

output "api_url" {
  value = "${aws_api_gateway_rest_api.api.execution_arn}/prod/users"
}
