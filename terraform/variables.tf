variable "kubeconfig_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "The kubeconfig context to use (e.g., kind-cloudpulse). If empty, uses the current context."
  type        = string
  default     = null
}

variable "namespace" {
  description = "The Kubernetes namespace where the application will be installed."
  type        = string
  default     = "cloudpulse"
}


variable "app_config" {
  description = "cloudpulse-config ConfigMap contents. Contains the same keys as k8s/configmap-secret.yaml."
  type        = map(string)
  default = {
    APP_NAME                       = "CloudPulse"
    APP_ENV                        = "production"
    APP_DEBUG                      = "false"
    APP_URL                        = "http://localhost:8080"
    APP_LOCALE                     = "en"
    APP_FALLBACK_LOCALE            = "en"
    APP_MAINTENANCE_DRIVER         = "file"
    BCRYPT_ROUNDS                  = "12"
    TRUSTED_PROXIES                = "*"
    LOG_CHANNEL                    = "stderr"
    LOG_LEVEL                      = "info"
    DB_CONNECTION                  = "mysql"
    DB_HOST                        = "mysql-primary"
    DB_READ_HOST                   = "mysql-replica"
    DB_PORT                        = "3306"
    DB_DATABASE                    = "cloudpulse"
    DB_USERNAME                    = "cloudpulse"
    DB_TIMEOUT                     = "3"
    DB_REPLICATION_USER            = "replicator"
    REDIS_CLIENT                   = "predis"
    REDIS_HOST                     = "redis"
    REDIS_PORT                     = "6379"
    SESSION_DRIVER                 = "redis"
    SESSION_LIFETIME               = "120"
    SESSION_ENCRYPT                = "false"
    CACHE_STORE                    = "redis"
    QUEUE_CONNECTION               = "redis"
    FILESYSTEM_DISK                = "s3"
    AWS_DEFAULT_REGION             = "us-east-1"
    AWS_BUCKET                     = "cloudpulse-uploads"
    AWS_ENDPOINT                   = "http://minio:9000"
    AWS_USE_PATH_STYLE_ENDPOINT    = "true"
    CLOUDPULSE_DISK                = "s3"
    CLOUDPULSE_MAX_UPLOAD_KB       = "10240"
    CLOUDPULSE_ALLOWED_EXTENSIONS  = "jpg,jpeg,png,pdf,txt,csv,zip"
    CLOUDPULSE_UPLOADS_PER_MINUTE  = "20"
    CLOUDPULSE_STATUS_POLL_SECONDS = "10"
    PHP_FPM_ADDRESS                = "127.0.0.1:9000"
    NGINX_CLIENT_MAX_BODY_SIZE     = "16m"
    PHP_UPLOAD_MAX_FILESIZE        = "12M"
    PHP_POST_MAX_SIZE              = "16M"
    PHP_FPM_MAX_CHILDREN           = "10"
  }
}


variable "app_key" {
  description = "Laravel APP_KEY (in base64:... format, 32 bytes). Generated with php artisan key:generate --show."
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(var.app_key, "base64:")
    error_message = "app_key must look like base64:<32 random bytes>."
  }
}

variable "db_root_password" {
  description = "MySQL root password."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_root_password) >= 16
    error_message = "db_root_password must be at least 16 characters."
  }
}

variable "db_password" {
  description = "Password for the application database user."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "db_password must be at least 16 characters."
  }
}

variable "db_replication_password" {
  description = "Password for the MySQL replication user."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_replication_password) >= 16
    error_message = "db_replication_password must be at least 16 characters."
  }
}

variable "redis_password" {
  description = "Redis password."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.redis_password) >= 16
    error_message = "redis_password must be at least 16 characters."
  }
}

variable "minio_root_user" {
  description = "Object storage root username (access key)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.minio_root_user) >= 3
    error_message = "minio_root_user must be at least 3 characters."
  }
}

variable "minio_root_password" {
  description = "Object storage root password (secret key)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.minio_root_password) >= 16
    error_message = "minio_root_password must be at least 16 characters."
  }
}


variable "create_image_pull_secret" {
  description = "If true, creates an image pull secret for GHCR (required for private packages)."
  type        = bool
  default     = false
}

variable "registry_server" {
  description = "Container registry server."
  type        = string
  default     = "ghcr.io"
}

variable "ghcr_username" {
  description = "GHCR username (GitHub username)."
  type        = string
  default     = ""
}

variable "ghcr_pat" {
  description = "read:packages authorized GitHub Personal Access Token."
  type        = string
  default     = ""
  sensitive   = true
}
