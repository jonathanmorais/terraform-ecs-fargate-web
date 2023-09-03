resource "aws_lb_target_group" "alb_tg" {
  count                = var.alb.enable ? 1 : 0
  name                 = local.service_id
  port                 = var.container.port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.network.vpc
  deregistration_delay = var.tg.deregistration_delay

  health_check {
    path                = var.tg.health_check_path
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = var.tg.health_check_healthy_threshold
    unhealthy_threshold = var.tg.health_check_unhealthy_threshold
    timeout             = var.tg.health_check_timeout
    interval            = var.tg.interval
    matcher             = "200"
  }

  lifecycle {
      create_before_destroy = true
      ignore_changes        = [name]
    }
}

resource "aws_lb" "alb" {
  count                      = var.alb.enable ? 1 : 0
  name                       = local.service_id
  internal                   = ! var.alb.public
  load_balancer_type         = "application"
  security_groups            = var.alb.security_groups
  subnets                    = var.alb.subnets
  enable_deletion_protection = var.alb.enable_deletion_protection
  tags                       = var.tags
  idle_timeout               = var.alb.idle_timeout

}

resource "aws_lb_listener" "alb_listener_http" {
  count             = var.alb.enable ? 1 : 0
  load_balancer_arn = aws_lb.alb[count.index].arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg[count.index].arn
  }

  depends_on = [aws_lb.alb, aws_lb_target_group.alb_tg]
}

data "aws_acm_certificate" "acm_certificate" {
  count = var.alb.enable && var.alb.certificate_domain != "" ? 1 : 0
  domain      = var.alb.certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
}

resource "aws_alb_listener" "alb_listener_https" {
  count             = var.alb.enable && var.alb.certificate_domain != "" ? 1 : 0
  load_balancer_arn = aws_lb.alb[count.index].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.acm_certificate[count.index].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg[count.index].arn
  }
  depends_on = [aws_lb.alb, aws_lb_target_group.alb_tg]
}

resource "aws_lb_listener_rule" "redirect_http_to_https" {
  count        = var.alb.redirect_to_https && var.alb.enable && var.alb.certificate_domain != "" ? 1 : 0
  listener_arn = aws_lb_listener.alb_listener_http[count.index].arn

  action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.scale.max
  min_capacity       = var.scale.min
  resource_id        = "service/${data.aws_ecs_cluster.cluster.cluster_name}/${aws_ecs_service.application.name}"
  role_arn           = data.aws_iam_role.ecs_task_execution_role.arn
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_policy" {
  name               = "${local.service_id}-autoscale"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.scale.cpu
    scale_in_cooldown  = "180" # seconds
    scale_out_cooldown = "60"  # seconds
  }
}

data aws_ecs_cluster "cluster" {
  cluster_name = var.cluster
}


resource "aws_ecs_service" "application" {
  name                              = local.service_id
  desired_count                     = var.scale.min
  cluster                           = data.aws_ecs_cluster.cluster.arn
  task_definition                   = aws_ecs_task_definition.service.arn
  enable_ecs_managed_tags           = true
  propagate_tags                    = "SERVICE"
  health_check_grace_period_seconds = var.container.health_check_grace_period_seconds

  network_configuration {
    subnets         = var.network.subnets
    security_groups = var.network.security_groups
  }

  dynamic "load_balancer" {
     for_each = var.alb.enable == true ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.alb_tg[0].arn
      container_name   = local.service_id
      container_port   = var.container.port
    }
  }

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight = 1
  }

  depends_on = [
    aws_lb_listener.alb_listener_http,
  aws_ecs_task_definition.service]

  lifecycle {
    // create an ECS service with an initial count of running instances,
    // then ignore any changes to that count caused externally (e.g. Application Autoscaling).
    ignore_changes = [desired_count]
  }

  tags = var.tags
}

data "template_file" "ecs_task_definition" {
  template = file("${path.module}/task-definitions/service.tpl.json")

  vars = {
    log_group   = aws_cloudwatch_log_group.ecs_service_logs.name
    service_id  = local.service_id
    image       = var.container.image
    cpu         = var.container.cpu
    memory      = var.container.memory
    port        = var.container.port
    environment = jsonencode(var.environment)
    command     = jsonencode(var.command)
  }
}

resource "aws_ecs_task_definition" "service" {
  family                = local.service_id
  container_definitions = data.template_file.ecs_task_definition.rendered
  cpu                   = var.container.cpu
  memory                = var.container.memory
  network_mode          = "awsvpc"
  task_role_arn         = data.aws_iam_role.ecs_task_execution_role.arn
  execution_role_arn    = data.aws_iam_role.ecs_task_execution_role.arn
  tags                  = var.tags

  depends_on = [
  aws_iam_role.service]
}

resource "aws_cloudwatch_log_group" "ecs_service_logs" {
  name_prefix       = "/ecs/${local.service_id}"
  retention_in_days = 7
  tags              = var.tags
}

data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_iam_role" "service" {
  name = "ecsTaskRole-${local.service_id}"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF


  tags = var.tags
}


resource "aws_iam_role_policy" "service" {
  name   = "ecsTaskRolePolicy-${local.service_id}"
  role   = aws_iam_role.service.id
  policy = file("${path.cwd}/${var.service_policy}")
}
