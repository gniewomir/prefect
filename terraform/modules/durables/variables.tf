variable "names" {
  description = "Provider names for Durable resources."
  type = object({
    project = string
    volume  = string
  })
}

variable "region" {
  description = "DigitalOcean region for regional Durables."
  type        = string
}

variable "domains" {
  description = "Configured Domain zones and their A-record names."
  type = map(object({
    names = list(string)
  }))
}

variable "allow_destroy" {
  description = "Teardown-only half of the Durable destruction unlock."
  type        = bool
}
