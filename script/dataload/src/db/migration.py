import os
from .postgres import PostgresConnection

BASE = os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "script")

def run_migrations(pg: PostgresConnection):
  scripts = [
        "01_ddl_estrutura/reset.sql",
        "01_ddl_estrutura/001_tipos.sql",
        "01_ddl_estrutura/002_tabelas.sql", # TODO: Adcionar indices quando o erick fazer
        "02_objetos_logicos/001_functions.sql",
        "02_objetos_logicos/002_triggers.sql",
  ]

  for script in scripts:
    pg.execute_sql_file(os.path.join(BASE, script))
    print(f"[MIGRATION] Script {script} executado com sucesso.")





