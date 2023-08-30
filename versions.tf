
terraform {
  required_version = ">= 0.13"
  required_providers {

    google = {
      source  = "hashicorp/google"
      version = ">= 3.53, < 5.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.2.2"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 2.1.0"
    }
  }

  provider_meta "google" {
    module_name = "blueprints/terraform/terraform-google-gcloud/v3.1.2"
  }

}
