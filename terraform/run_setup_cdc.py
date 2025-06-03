# run_setup_cdc.py

import psycopg2
import os

# Read connection info from environment variables (Terraform will set these)
PG_HOST     = os.environ["PG_HOST"]
PG_PORT     = os.environ["PG_PORT"]
PG_USER     = os.environ["PG_USER"]
PG_PASSWORD = os.environ["PG_PASSWORD"]
PG_DBNAME   = os.environ["PG_DBNAME"]

# Path to the SQL file
SQL_FILE_PATH = os.environ.get("SQL_FILE", "setup_cdc.pgsql")

def main():
    conn_string = (
        f"host={PG_HOST} "
        f"port={PG_PORT} "
        f"user={PG_USER} "
        f"password={PG_PASSWORD} "
        f"dbname={PG_DBNAME} "
        "sslmode=require"
    )
    conn = psycopg2.connect(conn_string)
    cur = conn.cursor()

    with open(SQL_FILE_PATH, "r") as f:
        sql = f.read()

    cur.execute(sql)
    conn.commit()
    cur.close()
    conn.close()

    print("setup_cdc.pgsql executed successfully.")

if __name__ == "__main__":
    main()
