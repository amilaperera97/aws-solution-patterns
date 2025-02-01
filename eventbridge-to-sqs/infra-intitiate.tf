################################################################
# SQS Resources (Main Queue + DLQ)
################################################################
resource "aws_sqs_queue" "dlq" {
  name                      = "event-processor-dlq"
  message_retention_seconds = 1209600 # 14 days
}


resource "aws_sqs_queue" "main" {
  name                      = "event-processor-queue"
  message_retention_seconds = 345600 # 4 days
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      "Version" : "2012-10-17",
      "Id" : "sqs-policy",
      "Statement" : [
        {
          "Sid" : "AllowEventBusToSendMessage",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "events.amazonaws.com"
          },
          "Action" : "sqs:SendMessage",
          "Resource" : aws_sqs_queue.main.arn,
          "Condition" : {
            "ArnEquals" : {
              "aws:SourceArn" : aws_cloudwatch_event_bus.source_bus.arn
            }
          }
        }
      ]
    }]
  })
}

################################################################
# EventBridge Source Bus and Rule
################################################################
resource "aws_cloudwatch_event_bus" "source_bus" {
  name = "source-event-bus"
}

resource "aws_cloudwatch_event_rule" "source_rule" {
  name           = "send-to-sqs"
  event_bus_name = aws_cloudwatch_event_bus.source_bus.name
  event_pattern = jsonencode({
    "detail" : {
      "name" : ["test"]
    }
  })
}

resource "aws_cloudwatch_event_target" "sqs_target" {
  rule           = aws_cloudwatch_event_rule.source_rule.name
  event_bus_name = aws_cloudwatch_event_bus.source_bus.name
  arn            = aws_sqs_queue.main.arn
  target_id      = "send-to-sqs"
}

resource "aws_iam_role" "eventbridge_to_sqs" {
  name = "EventBridgeToSQS-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "events.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_sqs_policy" {
  name = "EventBridgeSQSPolicy"
  role = aws_iam_role.eventbridge_to_sqs.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "sqs:SendMessage",
      Resource = aws_sqs_queue.main.arn
    }]
  })
}

################################################################
# Lambda Function
################################################################
resource "aws_lambda_function" "processor" {
  function_name = "sqs-event-processor"
  runtime       = "python3.9"
  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_exec.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda/lambda_function.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "LambdaExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_sqs" {
  name = "LambdaSQSPolicy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      Resource = aws_sqs_queue.main.arn
    }]
  })
}

# New CloudWatch Logs policy
resource "aws_iam_role_policy" "lambda_cloudwatch_logs" {
  name = "LambdaCloudWatchLogsPolicy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:eu-west-1:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_eventbridge" {
  name = "LambdaEventBridgePolicy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "events:PutEvents",
      Resource = aws_cloudwatch_event_bus.destination_bus.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.processor.function_name}"
  retention_in_days = 7
}


resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10
}

################################################################
# EventBridge Destination Bus
################################################################
resource "aws_cloudwatch_event_bus" "destination_bus" {
  name = "processed-events-bus"
}
