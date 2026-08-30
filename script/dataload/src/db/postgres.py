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
        cols = rows[0].keys()
        query = f"INSERT INTO {table_name} ({', '.join(cols)}) VALUES %s"
        values = []
        for r in rows:
            linhas = tuple(r[col] for col in cols)
            values.append(linhas)
        with self.conn.cursor() as cur:
            execute_values(cur, query, values)
        self.conn.commit()

    def close(self):
        if self.conn:
            self.conn.close()
