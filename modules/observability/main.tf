locals {
  alarm_actions = [aws_sns_topic.platform.arn]
}

resource "aws_sns_topic" "platform" {
  name = "${var.name_prefix}-platform-alarms"

  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = var.alarm_email_addresses

  endpoint  = each.value
  protocol  = "email"
  topic_arn = aws_sns_topic.platform.arn
}

resource "aws_cloudwatch_log_group" "platform" {
  kms_key_id        = null
  name              = "/platform/${var.environment}/host"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_actions       = local.alarm_actions
  alarm_description   = "Shared host CPU utilization is high"
  alarm_name          = "${var.name_prefix}-host-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  ok_actions          = local.alarm_actions
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold_percent
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = var.instance_id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_actions       = local.alarm_actions
  alarm_description   = "Shared host failed an EC2 status check"
  alarm_name          = "${var.name_prefix}-host-status-check"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  ok_actions          = local.alarm_actions
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = var.instance_id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "memory" {
  count = var.enable_agent_alarms ? 1 : 0

  alarm_actions       = local.alarm_actions
  alarm_description   = "Shared host memory utilization is high"
  alarm_name          = "${var.name_prefix}-host-memory-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  ok_actions          = local.alarm_actions
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_threshold_percent
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = var.instance_id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "disk" {
  count = var.enable_agent_alarms ? 1 : 0

  alarm_actions       = local.alarm_actions
  alarm_description   = "Shared host root filesystem utilization is high"
  alarm_name          = "${var.name_prefix}-host-disk-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  ok_actions          = local.alarm_actions
  period              = 300
  statistic           = "Average"
  threshold           = var.disk_threshold_percent
  treat_missing_data  = "breaching"

  dimensions = {
    device     = var.disk_device
    fstype     = var.disk_fstype
    InstanceId = var.instance_id
    path       = var.disk_path
  }

  tags = var.tags
}

resource "aws_cloudwatch_dashboard" "platform" {
  dashboard_name = "${var.name_prefix}-platform"
  dashboard_body = jsonencode({
    widgets = [
      {
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", var.instance_id],
            ["CWAgent", "mem_used_percent", "InstanceId", var.instance_id],
          ]
          period = 300
          region = data.aws_region.current.region
          stat   = "Average"
          title  = "Host CPU and memory"
          view   = "timeSeries"
        }
        type  = "metric"
        width = 12
        x     = 0
        y     = 0
      },
      {
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", var.instance_id],
            [".", "NetworkOut", ".", "."],
          ]
          period = 300
          region = data.aws_region.current.region
          stat   = "Sum"
          title  = "Host network"
          view   = "timeSeries"
        }
        type  = "metric"
        width = 12
        x     = 12
        y     = 0
      },
    ]
  })
}

data "aws_region" "current" {}

