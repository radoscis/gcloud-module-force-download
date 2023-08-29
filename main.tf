/**
 * Copyright 2018 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  tmp_credentials_path = "${path.module}/terraform-google-credentials.json"
  cache_path           = "${path.module}/cache/${random_id.cache.hex}"
  gcloud_tar_path      = "${local.cache_path}/google-cloud-sdk.tar.gz"
  gcloud_bin_path      = "${local.cache_path}/google-cloud-sdk/bin"
  gcloud_bin_abs_path  = abspath(local.gcloud_bin_path)
  components           = join(",", var.additional_components)
  
  gcloud              = "${local.gcloud_bin_path}/gcloud"
  gcloud_download_url = "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${var.gcloud_sdk_version}-${var.platform}-x86_64.tar.gz"
  jq_platform         = var.platform
  jq_download_url     = "https://github.com/stedolan/jq/releases/download/jq-${var.jq_version}/jq-${local.jq_platform}64"

  create_cmd_bin  = "${local.gcloud_bin_path}/${var.create_cmd_entrypoint}"
  destroy_cmd_bin = "${local.gcloud_bin_path}/${var.destroy_cmd_entrypoint}"

  wait = length(null_resource.run_command.*.triggers) + length(null_resource.run_destroy_command.*.triggers)

  prepare_cache_command                        = "mkdir -p ${local.cache_path}"
  download_gcloud_command                      = "curl -sL -o ${local.cache_path}/google-cloud-sdk.tar.gz ${local.gcloud_download_url}"
  download_jq_command                          = "curl -sL -o ${local.cache_path}/jq ${local.jq_download_url} && chmod +x ${local.cache_path}/jq"
  decompress_command                           = "tar -xzf ${local.gcloud_tar_path} -C ${local.cache_path} && cp ${local.cache_path}/jq ${local.cache_path}/google-cloud-sdk/bin/"
  decompress_wrapper                           = "${local.prepare_cache_command} && ${local.download_gcloud_command} && ${local.download_jq_command} && ${local.decompress_command}"
  additional_components_command                = "${path.module}/scripts/check_components.sh ${local.gcloud} ${local.components}"
  
}

resource "random_id" "cache" {
  byte_length = 4
}

resource "null_resource" "module_depends_on" {
  count = length(var.module_depends_on) > 0 ? 1 : 0

  triggers = {
    value = length(var.module_depends_on)
  }
}

resource "null_resource" "prepare_cache" {

  triggers = {
     always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    when    = create
    command = local.prepare_cache_command
  }

  depends_on = [null_resource.module_depends_on]
}

resource "null_resource" "download_gcloud" {
  
  triggers = {
     always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    when    = create
    command = local.download_gcloud_command
  }

  depends_on = [null_resource.prepare_cache]
}

resource "null_resource" "download_jq" {

  triggers = {
     always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    when    = create
    command = local.download_jq_command
  }

  depends_on = [null_resource.prepare_cache]
}

resource "null_resource" "decompress" {

  triggers = {
     always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    when    = create
    command = local.decompress_command
  }

  depends_on = [null_resource.download_gcloud, null_resource.download_jq]
}


resource "null_resource" "run_command" {
  count = var.enabled ? 1 : 0

  depends_on = [
    null_resource.module_depends_on,
    null_resource.decompress,
  ]

  triggers = merge({
    md5                   = md5(var.create_cmd_entrypoint)
    arguments             = md5(var.create_cmd_body)
    create_cmd_entrypoint = var.create_cmd_entrypoint
    create_cmd_body       = var.create_cmd_body
    gcloud_bin_abs_path   = local.gcloud_bin_abs_path
  }, var.create_cmd_triggers)

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
    PATH=${self.triggers.gcloud_bin_abs_path}:$PATH
    ${self.triggers.create_cmd_entrypoint} ${self.triggers.create_cmd_body}
    EOT
  }

}

resource "null_resource" "run_destroy_command" {
  count = var.enabled ? 1 : 0

  depends_on = [
    null_resource.module_depends_on,
    null_resource.decompress
  ]

  triggers = merge({
    destroy_cmd_entrypoint = var.destroy_cmd_entrypoint
    destroy_cmd_body       = var.destroy_cmd_body
    gcloud_bin_abs_path    = local.gcloud_bin_abs_path
  }, var.create_cmd_triggers)

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
    PATH=${self.triggers.gcloud_bin_abs_path}:$PATH
    ${self.triggers.destroy_cmd_entrypoint} ${self.triggers.destroy_cmd_body}
    EOT
  }
}

