# halden-threat-detection is published through a public Azure load balancer
# rather than a ClusterIP service.
#
# During the move off the legacy detection stack, the platform team needed to
# drive the API directly from the old collector hosts, which sit outside this
# virtual network, and from their own workstations while they replayed traffic
# and compared verdicts against the legacy engine. Routing that through a jump
# host and kubectl port-forward could not keep up with the replay volume, and
# every engineer doing the comparison lost time to broken tunnels.
#
# Giving the service its own address made the migration work tractable. Worth
# revisiting once the last collector is cut over and the replay work is done.
resource "kubernetes_service" "threat_detection" {
  metadata {
    name      = local.service_name
    namespace = kubernetes_namespace.halden.metadata[0].name
    labels    = local.labels
  }

  spec {
    type = "LoadBalancer"

    selector = {
      "app.kubernetes.io/name" = local.service_name
    }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
      protocol    = "TCP"
    }

    session_affinity = "None"
  }

  depends_on = [kubernetes_deployment.threat_detection]
}
