variable "default_region" {
  type    = string
  default = "eu-west-1"
}

variable "pull_event_lambda_function_name" {
  type    = string
  default = "PullEventBridgeData"
}