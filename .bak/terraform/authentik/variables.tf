variable "external_domain" {
  type = string
}
variable "internal_domain" {
  type = string
}
variable "kubernetes_namespace" {
  type = string
}
variable "authentik_domain" {
  type = string
}
variable "external_kubernetes_ingress_class_name" {
  type    = string
  default = "external"
}
variable "internal_kubernetes_ingress_class_name" {
  type    = string
  default = "internal"
}
