resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "eks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }]
  })
} 

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
  

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

resource "aws_iam_role" "eks_nodes" {
  name = "${var.cluster_name}-eks-nodes-role"
    
  assume_role_policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
        }]
    })
  
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_eks_node_group" "main" {
  cluster_name = aws_eks_cluster.main.name
  node_role_arn = aws_iam_role.eks_nodes.arn
  subnet_ids = [
    aws_subnet.private[0].id,
    aws_subnet.private[1].id
  ]

scaling_config {
  desired_size = var.node_desired_size
  min_size     = var.node_min_size
  max_size     = var.node_max_size
}

  instance_types = [var.node_instance_type]
  


  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_read_only
  ]

  tags = {
    Name = "${var.cluster_name}-node-group"
  }
}

