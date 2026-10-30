variable "project_name" {
  description = "Name prefix for the flag bucket and distribution. Pass the same local.name_prefix the other modules get."
  type        = string
}

variable "environment" {
  description = "Environment this state manages. Becomes the key prefix of the published document: <environment>/flags.json."
  type        = string
}

variable "cache_ttl_seconds" {
  description = <<-EOT
    How long CloudFront serves a published document before revalidating with S3.

    This is the floor on how fast a flag change reaches a device that has not
    yet cached it, so it is the knob that decides whether a kill switch takes
    effect in a minute or an hour. Clients additionally revalidate with
    If-None-Match, which costs a 304 rather than a full transfer, so a short
    TTL here is cheap. `make flags-publish` invalidates the path anyway, so
    this mainly bounds the staleness of an unpublished edge.
  EOT
  type        = number
  default     = 60
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 (US/Europe) is the default because a flag document is a few kilobytes and the cost difference is rarely worth the extra edges."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "tags" {
  description = "Tags to apply to every resource in this module"
  type        = map(string)
  default     = {}
}
