locals {
  # The listener is TLS when a serving certificate is mounted, and mutual TLS
  # when a client CA is mounted alongside it. Both are empty before the
  # cutover, which leaves the service on plaintext 8000.
  tls_enabled   = var.tls_secret_name != ""
  mtls_enabled  = var.tls_client_ca_secret_name != ""
  service_port  = local.tls_enabled ? 8443 : 8000
  tls_mount_dir = "/etc/halden/tls"
}

locals {
  # Built from the server's own attributes so the host does not have to be
  # repeated in a variable. sslmode=require pairs with require_secure_transport
  # on the server.
  database_url = format(
    "postgresql://%s:%s@%s:5432/%s?sslmode=require",
    var.postgres_administrator_login,
    urlencode(var.postgres_administrator_password),
    azurerm_postgresql_flexible_server.detection.fqdn,
    azurerm_postgresql_flexible_server_database.detection.name,
  )
}

resource "kubernetes_secret" "runtime" {
  metadata {
    name      = "${local.service_name}-runtime"
    namespace = kubernetes_namespace.halden.metadata[0].name
    labels    = local.labels
  }

  type = "Opaque"

  data = {
    HALDEN_GATEWAY_KEY  = var.halden_gateway_key
    HALDEN_DATABASE_URL = local.database_url
  }
}

resource "kubernetes_deployment" "threat_detection" {
  metadata {
    name      = local.service_name
    namespace = kubernetes_namespace.halden.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas = var.replica_count

    selector {
      match_labels = {
        "app.kubernetes.io/name" = local.service_name
      }
    }

    strategy {
      type = "RollingUpdate"

      rolling_update {
        max_surge       = 1
        max_unavailable = 0
      }
    }

    template {
      metadata {
        labels = local.labels

        annotations = {
          # Roll the pods whenever the secret changes, so a rotated gateway key or
          # database password reaches the running fleet without a manual restart.
          "halden.io/runtime-secret-revision" = kubernetes_secret.runtime.metadata[0].resource_version
        }
      }

      spec {
        automount_service_account_token = false

        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          run_as_group    = 10001
          fs_group        = 10001

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name              = local.service_name
          image             = "${var.container_registry}/${local.service_name}:${var.image_tag}"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "http"
            container_port = local.service_port
            protocol       = "TCP"
          }

          # The container filesystem is read-only, so the service writes artifacts
          # to the mounted scratch volume below rather than its default location.
          env {
            name  = "HALDEN_ARTIFACT_DIR"
            value = "/var/lib/halden/artifacts"
          }

          env {
            name = "HALDEN_GATEWAY_KEY"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.runtime.metadata[0].name
                key  = "HALDEN_GATEWAY_KEY"
              }
            }
          }

          # Required by the service and read at startup: without it the
          # container exits before it serves a request. Carried as a plain
          # value rather than through the runtime secret because a public key
          # is not secret, and keeping it out of the secret means rotating the
          # signing keypair does not roll pods on the secret's revision.
          env {
            name  = "HALDEN_INTERNAL_TOKEN_PUBLIC_KEY"
            value = var.halden_internal_token_public_key
          }

          env {
            name  = "HALDEN_LISTEN_PORT"
            value = tostring(local.service_port)
          }

          # Empty until the certificate is mounted. The service refuses to
          # start on one of the pair without the other, so these move together.
          env {
            name  = "HALDEN_TLS_CERT_FILE"
            value = local.tls_enabled ? "${local.tls_mount_dir}/tls.crt" : ""
          }

          env {
            name  = "HALDEN_TLS_KEY_FILE"
            value = local.tls_enabled ? "${local.tls_mount_dir}/tls.key" : ""
          }

          env {
            name  = "HALDEN_TLS_CLIENT_CA_FILE"
            value = local.mtls_enabled ? "${local.tls_mount_dir}-client-ca/ca.crt" : ""
          }

          env {
            name = "HALDEN_DATABASE_URL"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.runtime.metadata[0].name
                key  = "HALDEN_DATABASE_URL"
              }
            }
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }

            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }

          readiness_probe {
            http_get {
              path   = "/healthz"
              port   = "http"
              scheme = local.tls_enabled ? "HTTPS" : "HTTP"
            }

            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          liveness_probe {
            http_get {
              path   = "/healthz"
              port   = "http"
              scheme = local.tls_enabled ? "HTTPS" : "HTTP"
            }

            initial_delay_seconds = 20
            period_seconds        = 20
            timeout_seconds       = 5
            failure_threshold     = 5
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            privileged                 = false

            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          volume_mount {
            name       = "artifacts"
            mount_path = "/var/lib/halden/artifacts"
          }

          dynamic "volume_mount" {
            for_each = local.tls_enabled ? [1] : []

            content {
              name       = "tls"
              mount_path = local.tls_mount_dir
              read_only  = true
            }
          }

          dynamic "volume_mount" {
            for_each = local.mtls_enabled ? [1] : []

            content {
              name       = "tls-client-ca"
              mount_path = "${local.tls_mount_dir}-client-ca"
              read_only  = true
            }
          }
        }

        volume {
          name = "tmp"

          empty_dir {
            medium     = "Memory"
            size_limit = "64Mi"
          }
        }

        volume {
          name = "artifacts"

          empty_dir {
            size_limit = "2Gi"
          }
        }

        dynamic "volume" {
          for_each = local.tls_enabled ? [1] : []

          content {
            name = "tls"

            secret {
              secret_name = var.tls_secret_name
            }
          }
        }

        dynamic "volume" {
          for_each = local.mtls_enabled ? [1] : []

          content {
            name = "tls-client-ca"

            secret {
              secret_name = var.tls_client_ca_secret_name
            }
          }
        }
      }
    }
  }
}
