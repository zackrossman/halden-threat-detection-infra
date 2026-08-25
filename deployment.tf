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
            container_port = 8000
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
              path = "/healthz"
              port = "http"
            }

            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
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
      }
    }
  }
}
