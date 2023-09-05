# terraform-ecs-fargate-web

### use

```hcl
module "app-challenge_v2" {
  source  = "github.com/jonathanmorais/terraform-ecs-fargate-web"
  cluster = aws_ecs_cluster.this.name
  application = {
    name        = "app-challenge"
    version     = "v2"
    environment = "dev"
  }
  container = {
    image                             = "${var.image}:${var.image_tag}"
    cpu                               = 1024
    memory                            = 2048
    port                              = 8080
    health_check_grace_period_seconds = 300
  }
  scale = {
    cpu = 50
    min = 1
    max = 2
  }
  environment = [
    { name : "APP_PROFILE", value : "develop" },
    { name : "AWS_REGION", value : "us-east-1" }
  ]

  network = {
    vpc             = "vpc-123"
    subnets         = ["subnet-123", "subnet-123"]
    security_groups = ["sg-123"]
  }
  service_policy = "policies/poc.json"
  assign_public_ip = true
  tags = local.tags

  capacity_provider = "FARGATE_SPOT"

  alb = {
    enable                     = true
    public                     = true
    certificate_domain         = ""
    idle_timeout               = 300
    health                     = "/"
    enable_deletion_protection = false
    redirect_to_https          = true
    subnets                    = ["subnet-123", "subnet-123"]
    security_groups            = ["sg-123c"]
  }
}
```
