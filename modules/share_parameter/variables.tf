# ---------- modules/share_parameter/variables.tf ----------

variable "parameters" {
  description = "List of parameters to share."
  type        = map(string)
}