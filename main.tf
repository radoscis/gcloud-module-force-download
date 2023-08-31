
locals {
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

resource "null_resource" "run_command" {
  count = var.enabled ? 1 : 0

  depends_on = [
    null_resource.module_depends_on,
  ]

  triggers = merge({
    md5                   = md5(var.create_cmd_entrypoint)
    arguments             = md5(var.create_cmd_body)
    create_cmd_entrypoint = var.create_cmd_entrypoint
    create_cmd_body       = var.create_cmd_body
    gcloud_bin_path       = local.gcloud_bin_path
  }, var.create_cmd_triggers)

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
    ${local.decompress_wrapper}
    "${self.triggers.gcloud_bin_path}/${self.triggers.create_cmd_entrypoint}" ${self.triggers.create_cmd_body} > "${path.module}/cmd_run_output.txt"
    EOT
  }

}

resource "null_resource" "run_destroy_command" {
  count = var.enabled ? 1 : 0

  depends_on = [
    null_resource.module_depends_on
  ]

  triggers = merge({
    destroy_cmd_entrypoint = var.destroy_cmd_entrypoint
    destroy_cmd_body       = var.destroy_cmd_body
    decompress_wrapper     = local.decompress_wrapper
    gcloud_bin_path       = local.gcloud_bin_path
  }, var.create_cmd_triggers)

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
    ${self.triggers.decompress_wrapper}
    "${self.triggers.gcloud_bin_path}/${self.triggers.destroy_cmd_entrypoint}" ${self.triggers.destroy_cmd_body}
    EOT
  }
}

data "local_file" "run_cmd_output" {
  depends_on = [null_resource.run_command]
  filename = "${path.module}/cmd_run_output.txt"
  
}
