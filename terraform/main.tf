terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = ">= 4.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.1.0"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}

# 1) Aiven PostgreSQL

resource "aiven_pg" "postgres" {
  project       = var.aiven_project
  cloud_name    = "google-europe-west1"
  service_name  = "cdc-pg"
  plan          = "startup-4"

  maintenance_window_dow  = "monday"
  maintenance_window_time = "03:00:00"

  pg_user_config {
    public_access {
      pg         = true
      prometheus = false
    }
    pg {
      idle_in_transaction_session_timeout = 900
      log_min_duration_statement          = -1
    }
  }
}

# 2) Aiven Kafka

resource "aiven_kafka" "kafka" {
  project      = var.aiven_project
  cloud_name   = "google-europe-west1"
  service_name = "cdc-kafka"
  plan         = "startup-2"

  maintenance_window_dow  = "tuesday"
  maintenance_window_time = "02:00:00"

  kafka_user_config {
    kafka_version = "3.8"

    kafka {
      group_max_session_timeout_ms = 70000
      log_retention_bytes          = 1000000000
      auto_create_topics_enable    = true
    }

    public_access {
      kafka         = true
      kafka_rest    = true
      kafka_connect = true
    }
  }
}

# Kafka topic “cdc-sharing”

resource "aiven_kafka_topic" "cdc_sharing" {
  project      = var.aiven_project
  service_name = aiven_kafka.kafka.service_name
  topic_name   = "cdc-sharing"
  partitions   = 1
  replication  = 2
  termination_protection = false


  # config = {
  #   name  = "flush.ms"
  #   value = "10"
  # }
  # config = {
  #   name  = "cleanup.policy"
  #   value = "delete"
  # }
}

# 3) Aiven OpenSearch

resource "aiven_opensearch" "opensearch" {
  project      = var.aiven_project
  cloud_name   = "google-europe-west1"
  service_name = "cdc-opensearch"
  plan         = "startup-4"

  maintenance_window_dow  = "thursday"
  maintenance_window_time = "02:00:00"

  opensearch_user_config {
    opensearch_version = 2

    opensearch_dashboards {
      enabled                    = true
      opensearch_request_timeout = 30000
    }

    public_access {
      opensearch            = true
      opensearch_dashboards = true
    }
  }
}

# 4) Aiven Kafka Connect

resource "aiven_kafka_connect" "connect" {
  project      = var.aiven_project
  cloud_name   = "google-europe-west1"
  service_name = "cdc-kafka-connect"
  plan         = "startup-4"

  maintenance_window_dow  = "wednesday"
  maintenance_window_time = "02:00:00"

  kafka_connect_user_config {
    kafka_connect {
      consumer_isolation_level = "read_committed"
    }
  }
}

# 5) Integrate Kafka with Kafka Connect

resource "aiven_service_integration" "connect_integration" {
  project                  = var.aiven_project
  integration_type         = "kafka_connect"
  source_service_name      = aiven_kafka.kafka.service_name
  destination_service_name = aiven_kafka_connect.connect.service_name

  depends_on = [
    aiven_kafka_connect.connect,
    aiven_kafka.kafka
  ]
}

# 6) Write out DDL SQL for setting up customer table + publication

resource "local_file" "setup_sql" {
  filename        = "${path.module}/setup_cdc.pgsql"
  file_permission = "0644"
  content = <<-EOT
    -- 1) Create 'customer' table
    CREATE TABLE IF NOT EXISTS public.customer (
      id              SERIAL PRIMARY KEY,
      full_name       TEXT NOT NULL,
      email           TEXT UNIQUE NOT NULL,
      phone           TEXT,
      classification  VARCHAR(10) CHECK (classification IN ('public','private')) NOT NULL,
      created_at      TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
    );

    -- 2) Create replication user if not exists
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'debezium_user'
      ) THEN
        CREATE ROLE debezium_user WITH REPLICATION LOGIN PASSWORD 'StrongPassword123!';
      END IF;
    END
    $$;

    -- 3) Grant SELECT on public.customer to debezium_user
    GRANT SELECT ON public.customer TO debezium_user;

    -- 4) Create publication if not exists
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_publication
        WHERE pubname = 'customer_pub'
      ) THEN
        CREATE PUBLICATION customer_pub FOR TABLE public.customer;
      END IF;
    END
    $$;
  EOT
}

# 7) Run that SQL file against the Aiven Postgres service

resource "null_resource" "db_cdc_setup" {
  depends_on = [ aiven_pg.postgres ]

  provisioner "local-exec" {
    command = "python run_setup_cdc.py"

    environment = {
      PG_HOST     = aiven_pg.postgres.service_host
      PG_PORT     = tostring(aiven_pg.postgres.service_port)
      PG_USER     = aiven_pg.postgres.service_username
      PG_PASSWORD = aiven_pg.postgres.service_password
      PG_DBNAME   = "defaultdb"  # Aiven’s default DB name
      SQL_FILE    = "${path.module}/setup_cdc.pgsql"
    }
  }
}

# 
# 8) Debezium Postgres Source Connector 

resource "aiven_kafka_connector" "debezium_pg_source" {
  project        = var.aiven_project
  service_name   = aiven_kafka_connect.connect.service_name
  connector_name = "postgres-customer-cdc"

  depends_on = [
    aiven_service_integration.connect_integration,
    null_resource.db_cdc_setup
  ]

  config = {
    "name"                      = "postgres-customer-cdc"
    "connector.class"           = "io.debezium.connector.postgresql.PostgresConnector"
    "tasks.max"                 = "1"

    "database.hostname"         = aiven_pg.postgres.service_host
    "database.port"             = tostring(aiven_pg.postgres.service_port)
    "database.user"             = "debezium_user"
    "database.password"         = "StrongPassword123!"
    "database.dbname"           = "defaultdb"
    "database.server.name"      = aiven_pg.postgres.service_name

    "plugin.name"               = "pgoutput"
    "slot.name"                 = "debezium_slot"
    "publication.name"          = "customer_pub"
    "publication.autocreate.mode" = "disabled"

    "topic.prefix"                 = aiven_pg.postgres.service_name

    "table.include.list"        = "public.customer"
    "heartbeat.interval.ms"      = "300000"

    "transforms":                        "unwrap,setKey",
    "transforms.unwrap.type":            "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "false",
    "transforms.unwrap.delete.handling.mode": "rewrite",
    "transforms.setKey.type":            "org.apache.kafka.connect.transforms.ValueToKey",
    "transforms.setKey.fields":          "id",


    "key.converter"             = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter"           = "org.apache.kafka.connect.json.JsonConverter"
    "key.converter.schemas.enable"   = "false"
    "value.converter.schemas.enable" = "false"
  }
}

# 9) Outputs 

output "pg_host" {
  value = aiven_pg.postgres.service_host
}
output "pg_port" {
  value = aiven_pg.postgres.service_port
}
output "pg_user" {
  value = aiven_pg.postgres.service_username
}
output "pg_password" {
  value = aiven_pg.postgres.service_password
  sensitive = true
}

output "kafka_bootstrap_servers" {
  value = "${aiven_kafka.kafka.service_host}:${aiven_kafka.kafka.service_port}"
}
output "kafka_user" {
  value = aiven_kafka.kafka.service_username
}
output "kafka_password" {
  value = aiven_kafka.kafka.service_password
  sensitive = true
}

output "connect_uri" {
  value = aiven_kafka_connect.connect.service_host
}
output "connect_port" {
  value = aiven_kafka_connect.connect.service_port
}

output "os_url" {
  value = aiven_opensearch.opensearch.service_uri
  sensitive = true
}
output "os_username" {
  value = aiven_opensearch.opensearch.service_username
}
output "os_password" {
  value = aiven_opensearch.opensearch.service_password
  sensitive = true
}
