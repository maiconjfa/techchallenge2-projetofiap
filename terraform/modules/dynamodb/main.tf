###############################################################################
# Tabela DynamoDB ToggleMasterAnalytics
#
# Schema definido pelo analytics-service (analytics-service/app.py):
#   event_id  : S  (partition key, uuid gerado no worker)
#   user_id   : S
#   flag_name : S
#   result    : BOOL
#   timestamp : S
###############################################################################
resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = merge(var.tags, {
    Name = var.table_name
  })
}
