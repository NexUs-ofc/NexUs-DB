import argparse
import os

from .db.mongo import MongoConnection
from .db.postgres import PostgresConnection
from .seeders import mongo_seeder, postgres_seeder


def seed_sql(*, reset: bool = False):
    pg = PostgresConnection()
    try:
        postgres_seeder.run(pg, reset=reset)
    finally:
        pg.close()
    print("[OK] PostgreSQL populado.")


def seed_mongo(*, reset: bool = False):
    mongo = MongoConnection()
    try:
        mongo_seeder.run(mongo, reset=reset)
    finally:
        mongo.close()
    print("[OK] MongoDB populado.")


def main():
    parser = argparse.ArgumentParser(description="NexUs-DB dataload")
    parser.add_argument("comando", choices=["seed-sql", "seed-mongo", "all"])
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Reinicia os dados SQL e as collections Mongo autorizadas.",
    )
    parser.add_argument(
        "--perfil", choices=["padrao", "bi"], default="padrao",
        help="bi: acrescenta ~12 meses de uso simulado para BI (somente PostgreSQL).",
    )
    args = parser.parse_args()

    if args.perfil == "bi":
        from .bi import executar

        pg = PostgresConnection()
        try:
            executar(pg)
        except Exception:
            pg.rollback()
            raise
        finally:
            pg.close()
        print("[OK] Dados de BI carregados.")
        return

    if args.reset and os.getenv("DATALOAD_ALLOW_RESET", "").lower() != "true":
        parser.error(
            "Para usar --reset, defina DATALOAD_ALLOW_RESET=true no ambiente."
        )

    if args.comando in ("seed-sql", "all"):
        seed_sql(reset=args.reset)

    if args.comando in ("seed-mongo", "all"):
        seed_mongo(reset=args.reset)


if __name__ == "__main__":
    main()
