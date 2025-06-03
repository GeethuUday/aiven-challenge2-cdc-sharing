# raw_peek.py

import json
from kafka import KafkaConsumer
from config import KAFKA

consumer = KafkaConsumer(
    "cdc-pg.public.customer",              # or "<your-pg-service-name>.public.customer"
    bootstrap_servers=KAFKA["bootstrap_servers"].split(","),
    security_protocol="SSL",
    ssl_cafile=KAFKA["ssl_ca"],
    ssl_certfile=KAFKA["ssl_cert"],
    ssl_keyfile=KAFKA["ssl_key"],
    auto_offset_reset="earliest",
    enable_auto_commit=False,
    group_id="raw-peek-group",
    value_deserializer=lambda m: json.loads(m.decode("utf-8"))
)

print("Waiting for one raw Debezium message…")
for msg in consumer:
    print("Key   :", msg.key)
    print("Value :", json.dumps(msg.value, indent=2))
    break
consumer.close()
