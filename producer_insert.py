# producer_insert.py

import psycopg2
from faker import Faker
import random
from config import POSTGRES

faker = Faker()
CLASSIFICATIONS = ["public", "private"]

def insert_customer():
    conn = psycopg2.connect(
        host=POSTGRES["host"],
        port=POSTGRES["port"],
        user=POSTGRES["user"],
        password=POSTGRES["password"],
        dbname=POSTGRES["dbname"],
        sslmode=POSTGRES["sslmode"]
    )
    cur = conn.cursor()

    full_name = faker.name()
    email = faker.unique.email()
    phone = faker.phone_number()
    classification = random.choice(CLASSIFICATIONS)

    cur.execute(
        """
        INSERT INTO customer (full_name, email, phone, classification)
        VALUES (%s, %s, %s, %s)
        RETURNING id, full_name, email, phone, classification, created_at;
        """,
        (full_name, email, phone, classification)
    )
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()

    print("Inserted into Postgres:", {
        "id":             row[0],
        "full_name":      row[1],
        "email":          row[2],
        "phone":          row[3],
        "classification": row[4],
        "created_at":     row[5].isoformat()
    })

def update_customer(customer_id):
    conn = psycopg2.connect(
        host=POSTGRES["host"],
        port=POSTGRES["port"],
        user=POSTGRES["user"],
        password=POSTGRES["password"],
        dbname=POSTGRES["dbname"],
        sslmode=POSTGRES["sslmode"]
    )
    cur = conn.cursor()

    new_phone = faker.phone_number()
    cur.execute(
        "UPDATE customer SET phone = %s WHERE id = %s RETURNING id, full_name, email, phone, classification, created_at;",
        (new_phone, customer_id)
    )
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()

    print("Updated in Postgres:", {
        "id":             row[0],
        "full_name":      row[1],
        "email":          row[2],
        "phone":          row[3],
        "classification": row[4],
        "created_at":     row[5].isoformat()
    })

def delete_customer(customer_id):
    conn = psycopg2.connect(
        host=POSTGRES["host"],
        port=POSTGRES["port"],
        user=POSTGRES["user"],
        password=POSTGRES["password"],
        dbname=POSTGRES["dbname"],
        sslmode=POSTGRES["sslmode"]
    )
    cur = conn.cursor()
    cur.execute("DELETE FROM customer WHERE id = %s RETURNING id;", (customer_id,))
    deleted = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    print(f"Deleted from Postgres: id={deleted[0]}")

if __name__ == "__main__":
    print("1) Insert new customer\n2) Update existing customer\n3) Delete customer\nEnter choice (1/2/3): ", end="")
    choice = input().strip()
    if choice == "1":
        insert_customer()
    elif choice == "2":
        cid = input("Enter customer ID to update: ").strip()
        update_customer(int(cid))
    elif choice == "3":
        cid = input("Enter customer ID to delete: ").strip()
        delete_customer(int(cid))
    else:
        print("Unknown choice.")
