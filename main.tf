terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

provider "yandex" {
  token      = "token"
  cloud_id   = "id"
  folder_id  = "id"
  zone       = "ru-central1-a"
}

resource "yandex_iam_service_account" "ig-sa" {
  name        = "ig-sa"
  description = "service account to manage IG"
}

resource "yandex_resourcemanager_folder_iam_binding" "admin" {
  folder_id = "b1gb8kefqeahisn2e3c1"
  role      = "admin"
  members   = [
    "serviceAccount:${yandex_iam_service_account.ig-sa.id}",
  ]
}

resource "yandex_resourcemanager_folder_iam_member" "sa-editor" {
  folder_id = "id"
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.ig-sa.id}"
}

resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.ig-sa.id
  description        = "static access key for object storage"
}

resource "yandex_storage_bucket" "avpakhomov-bucket" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket = "avpakhomov-bucket"
}

resource "yandex_storage_object" "upload-image" {
  bucket = "avpakhomov-bucket"
  key    = "image.jpg"
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  source = "image.jpg"
  acl = "public-read"
}

resource "yandex_compute_instance_group" "ig-1" {
  name               = "ig-with-balancer"
  folder_id          = "id"
  service_account_id = "${yandex_iam_service_account.ig-sa.id}"
  instance_template {
    platform_id = "standard-v3"
    resources {
      memory = 2
      cores  = 2
      core_fraction = 20
    }
    
    boot_disk {
      initialize_params {
        image_id = "fd827b91d99psvq5fjit"
        size = 10
      }
    }

    network_interface {
      network_id = "${yandex_vpc_network.network-1.id}"
      subnet_ids = ["${yandex_vpc_subnet.subnet-1.id}"]
    }

    metadata = {
      ssh-keys = "ubuntu:${file("id_rsa.pub")}"
      user-data = "#cloud-config\nbootcmd:\n  - cd /var/www/html && echo '<html><h1><a href=https://storage.yandexcloud.net/avpakhomov-bucket/image.jpg><img src=https://storage.yandexcloud.net/avpakhomov-bucket/image.jpg></a></h1></html>' > index.html"
    }

    scheduling_policy {
      preemptible = true
    }
  }

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    zones = ["ru-central1-a"]
  }

  deploy_policy {
    max_unavailable = 1
    max_expansion   = 0
  }

}

resource "yandex_vpc_network" "network-1" {
  name = "network1"
}

resource "yandex_vpc_subnet" "subnet-1" {
  name           = "subnet1"
  zone           = "ru-central1-a"
  network_id     = "${yandex_vpc_network.network-1.id}"
  v4_cidr_blocks = ["192.168.10.0/24"]
}


data "yandex_compute_instance_group" "my_group" {
  instance_group_id = "${yandex_compute_instance_group.ig-1.id}"
}

resource "yandex_lb_target_group" "lb-target-group" {
  name      = "lb-target-group"
  region_id = "ru-central1"

  target {
    subnet_id = "${yandex_vpc_subnet.subnet-1.id}"
    address   = "${data.yandex_compute_instance_group.my_group.instances.0.network_interface.0.ip_address}"
  }

  target {
    subnet_id = "${yandex_vpc_subnet.subnet-1.id}"
    address   = "${data.yandex_compute_instance_group.my_group.instances.1.network_interface.0.ip_address}"
  }

  target {
    subnet_id = "${yandex_vpc_subnet.subnet-1.id}"
    address   = "${data.yandex_compute_instance_group.my_group.instances.2.network_interface.0.ip_address}"
  }
}

resource "yandex_lb_network_load_balancer" "my-network-load-balancer" {
  name = "my-network-load-balancer"

  listener {
    name = "my-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = "${yandex_lb_target_group.lb-target-group.id}"

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}
