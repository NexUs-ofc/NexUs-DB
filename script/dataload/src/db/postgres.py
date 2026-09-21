import psycopg2
from psycopg2.extras import execute_values

from ..config import get_env


class PostgresConnection:
    def __init__(self):
        self.conn = psycopg2.connect(
            host=get_env("PG_HOST"),
            port=get_env("PG_PORT"),
            dbname=get_env("PG_DATABASE"),
            user=get_env("PG_USER"),
            password=get_env("PG_PASSWORD"),
        )
        self.conn.autocommit = False

    def execute_sql_file(self, file_path: str):
        with open(file_path, 'r', encoding='utf-8') as f:
            with self.conn.cursor() as cur:
                cur.execute(f.read())
            self.conn.commit()
    def bulk_insert(self, table_name: str, rows: list[dict]):
        if not rows:
            return
        cols = list(dict.fromkeys(col for row in rows for col in row))
        query = f"INSERT INTO {table_name} ({', '.join(cols)}) VALUES %s"
        values = [tuple(row.get(col) for col in cols) for row in rows]
        with self.conn.cursor() as cur:
            execute_values(cur, query, values)

    def reset_seed_data(self):
        query = """
            TRUNCATE TABLE
                pantry_product_setting,
                pantry_item,
                payment,
                store,
                company,
                auth_method,
                profile_phone,
                profile,
                food,
                address,
                plan,
                category
            RESTART IDENTITY CASCADE;
        """
        with self.conn.cursor() as cur:
            cur.execute(query)

    def commit(self):
        self.conn.commit()

    def rollback(self):
        self.conn.rollback()

    def close(self):
        if self.conn:
            self.conn.close()
