# ---------- modules/retreive_parameters/variables.tf ----------

variable "parameters" {
  description = "List of parameters to retrieve."
  type = map(string)
}