###############################################################################
# Mensageria: fila SQS de eventos + Dead Letter Queue com redrive policy
###############################################################################

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = 1209600 # 14 dias

  tags = merge(var.tags, {
    Name = "${var.queue_name}-dlq"
  })
}

resource "aws_sqs_queue" "this" {
  name                       = var.queue_name
  visibility_timeout_seconds = 60
  receive_wait_time_seconds  = 10

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(var.tags, {
    Name = var.queue_name
  })
}
