# consumer_to_opensearch.py

import json
from kafka import KafkaConsumer
from opensearchpy import OpenSearch, RequestsHttpConnection
from config import KAFKA, OPENSEARCH

def ensure_index(os_client, index_name):
    """
    Create the OpenSearch index with mapping if it doesn’t exist.
    We index: id (integer), full_name (text), email (keyword), phone (keyword),
    classification (keyword), created_at (date).
    """
    if not os_client.indices.exists(index=index_name):
        mapping = {
            "mappings": {
                "properties": {
                    "id":             { "type": "integer" },
                    "full_name":      { "type": "text"    },
                    "email":          { "type": "keyword" },
                    "phone":          { "type": "keyword" },
                    "classification": { "type": "keyword" },
                    "created_at":     { "type": "date"    }
                }
            },
            "settings": {
                "number_of_shards":   1,
                "number_of_replicas": 1
            }
        }
        os_client.indices.create(index=index_name, body=mapping)
        print(f"Created OpenSearch index '{index_name}'")
    else:
        print(f"OpenSearch index '{index_name}' already exists")

def main():
    # 1) Connect to OpenSearch
    os_client = OpenSearch(
        hosts=[OPENSEARCH["url"]],
        http_auth=(OPENSEARCH["username"], OPENSEARCH["password"]),
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection
    )
    os_index = OPENSEARCH["index"]

    # 1a) Ensure index exists
    ensure_index(os_client, os_index)

    # 2) Connect to Kafka (Debezium topic)
    topic_name = "aiven-pg.public.customer"
    consumer = KafkaConsumer(
        "cdc-pg.public.customer",
        bootstrap_servers=KAFKA["bootstrap_servers"],
        security_protocol="SSL",
        ssl_cafile=KAFKA["ssl_ca"],
        ssl_certfile=KAFKA["ssl_cert"],
        ssl_keyfile=KAFKA["ssl_key"],
        auto_offset_reset="earliest",
        value_deserializer=lambda m: json.loads(m.decode("utf-8")),
        enable_auto_commit=True,
        group_id="customer-cdc-consumer"
    )

    print("Consumer started, waiting for CDC events… (Ctrl+C to stop)")
    try:
        for msg in consumer:
            event = msg.value

            # If value is None, this is a tombstone for a DELETE (after transform.drop.tombstones=false)
            if event is None:
                # If tombstone records appear, key will hold the ID
                if msg.key:
                    rec_id = int(msg.key.decode("utf-8"))
                    os_client.delete(index=os_index, id=rec_id, ignore=[404])
                    print(f"Deleted from OpenSearch: id={rec_id}")
                continue

            # With "delete.handling.mode=rewrite", event looks like {"op":"d","before":{…},"after":null}
            if "op" in event and event["op"] == "d":
                deleted_row = event["before"]
                rec_id = deleted_row["id"]
                os_client.delete(index=os_index, id=rec_id, ignore=[404])
                print(f"DELETE indexed in OpenSearch: id={rec_id}")
                continue

            # For inserts/updates: extract event["after"]
            if "after" in event and event["after"] is not None:
                doc = event["after"]
            else:
                # If unwrap left just the row itself
                doc = event

            rec_id = doc["id"]
            os_client.index(index=os_index, id=rec_id, body=doc)
            print(f"INSERT/UPDATE indexed in OpenSearch: {doc}")

    except KeyboardInterrupt:
        print("Stopping consumer…")

    finally:
        consumer.close()
        print("Consumer stopped.")

if __name__ == "__main__":
    main()
