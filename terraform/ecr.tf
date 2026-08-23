resource "aws_ecr_repository" "task_api" {
  name = "task-api"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}