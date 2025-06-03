
# Challenge 2: Change Data Capture (CDC) and Secure Data Sharing

This repository implements a full end-to-end CDC pipeline using Aiven PostgreSQL, Aiven Kafka (with Debezium), and Aiven OpenSearch. Whenever you INSERT/UPDATE/DELETE a record in Postgres, Debezium captures it, writes a message into Kafka, and a Python consumer indexes (or removes) it in OpenSearch in real time.

> **Note:** Database setup and Debezium connector registration are handled entirely via Terraform (no separate Python scripts needed for those steps). The “bonus” role-based security section of the challenge has been skipped.

## Repository Structure

```
.
├── config.py
├── Terraform/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── producer_insert.py
├── consumer_to_opensearch.py
├── peek.py
└── README.md  ← (this file)
```

- **`config.py`**  
  Holds configuration values (service hosts, ports, usernames, passwords, certificates) for Postgres, Kafka, Kafka Connect, and OpenSearch.

- **`Terraform/`**  
  All Terraform code to provision:
  1. Aiven PostgreSQL (with logical replication enabled)  
  2. Aiven Kafka (with public access & Connect enabled)  
  3. Aiven Kafka Connect (with the Debezium Postgres plugin)  
  4. A Debezium source connector (`aiven_kafka_connector`) capturing changes on `public.customer`  
  5. An Aiven OpenSearch cluster  
  6. Outputs for service URIs, ports, credentials, etc.

- **`producer_insert.py`**  
  A CLI-style Python script that lets you:
  1. Insert a fake customer (via Faker).  
  2. Update an existing customer’s phone by ID.  
  3. Delete a customer by ID.  
  Every operation/changes will be picked up by Debezium.

- **`consumer_to_opensearch.py`**  
  Subscribes to topic `cdc-pg.public.customer`, deserializes JSON, and:
  - If `msg.value is None` → delete doc with that key (DELETE tombstone).  
  - Else → index the flat JSON (INSERT/UPDATE) into the OpenSearch index `customer_cdc_index`.  
  It creates the index (with mapping) if it doesn’t exist.

- **`peek.py`**  
  A quick one-off script to “peek” a single Debezium message from Kafka. Useful to confirm Debezium → Kafka is working.

---

## Prerequisites

1. **Aiven account** with sufficient credits.  
2. **Local environment** with:
   - `terraform` v1.2+  
   - `python` 3.8+  
   - Python packages: `psycopg2-binary`, `kafka-python`, `opensearch-py`, `faker`, `requests`  
   - Aiven certificates: `ca.pem`, `service.cert`, `service.key`

Install Python dependencies with:
```bash
pip install psycopg2-binary kafka-python opensearch-py faker requests
```

3. **Git** (for pushing to GitHub).

---

## 1. Provision Aiven Services via Terraform

1. Open a terminal and `cd Terraform/`.
2. Create a file `terraform.tfvars` (or pass `-var` flags) with:
   ```hcl
   aiven_project   = "<YOUR_AIVEN_PROJECT_NAME>"
   aiven_api_token = "<YOUR_AIVEN_API_TOKEN>"
   ```
3. Initialize and apply:
   ```bash
   terraform init
   terraform apply
   ```
4. After Terraform completes, note the outputs:
   - PostgreSQL host/port/username/password  
   - Kafka bootstrap servers, certificates  
   - Kafka Connect endpoint, credentials, certificates  
   - OpenSearch endpoint, credentials  

5. Copy those values into **`config.py`**:
   ```python
   POSTGRES = {
       "host": "<postgres-host>",
       "port": <postgres-port>,
       "user": "<postgres-username>",
       "password": "<postgres-password>",
       "dbname": "defaultdb",
       "sslmode": "require"
   }

   KAFKA = {
       "topic": "cdc-pg.public.customer",
       "bootstrap_servers": "<kafka-host>:<port>",
       "ssl_ca": "ca.pem",
       "ssl_cert": "service.cert",
       "ssl_key": "service.key"
   }

   OPENSEARCH = {
       "url": "https://<opensearch-host>:<port>",
       "username": "<os-username>",
       "password": "<os-password>",
       "index": "customer_cdc_index"
   }
   ```

---

## 2. Test Postgres → Kafka (Debezium)

1. Run the producer script to insert/update/delete:
   ```bash
   python producer_insert.py
   ```
   - Choose **1** to insert a new customer; note the printed record (e.g., `{'id': 4, ...}`).

---

## 2. Start the OpenSearch Consumer

```bash
python consumer_to_opensearch.py
```
You should see:
```
OpenSearch index 'customer_cdc_index' already exists
Consumer started, waiting for CDC events…
Indexed (insert/update) in OpenSearch: {'id': 4, 'full_name': 'John Smith', ...}
```
Now, if you query OpenSearch or load Dashboards, that document will appear.

---

## 3. Visualize in OpenSearch Dashboards

1. **Create Index Pattern**  
   - Stack Management → Index Patterns → Create index pattern →  
     `customer_cdc_index*` → Next → Time field = `created_at` → Create.

2. **Bar Chart: “Count by Classification”**  
   - Visualize → Create visualization → Vertical bar → select index `customer_cdc_index*`  
   - X-Axis: Terms on `classification.keyword`, order by count → Save as “Count by Classification”.

3. **Line Chart: “New Customers Over Time”**  
   - Visualize → Create visualization → Line → select index `customer_cdc_index*`  
   - X-Axis: Date histogram on `created_at` → Save as “New Customers Over Time”.

4. **Saved Search: “Recent 10 Customers”**  
   - Discover → select index `customer_cdc_index*`, sort `created_at` descending →  
     Save search as “Recent 10 Customers”.

5. **Dashboard: “Customer CDC Dashboard”**  
   - Dashboard → Create → Add from library: “Count by Classification”, “New Customers Over Time”, “Recent 10 Customers” → Arrange and Save.

