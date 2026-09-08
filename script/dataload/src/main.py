import argparse

from .db.migration import run_migrations
from .db.mongo import MongoConnection
from .db.postgres import PostgresConnection
from .seeders import mongo_seeder, postgres_seeder


def seed_sql():
    pg = PostgresConnection()
    postgres_seeder.run(pg)
    pg.close()
    print("[OK] PostgreSQL populado.")


def seed_mongo():
    mongo = MongoConnection()
    mongo_seeder.run(mongo)
    mongo.close()
    print("[OK] MongoDB populado.")


def main():
    parser = argparse.ArgumentParser(description="NexUs-DB dataload")
    parser.add_argument("comando", choices=["init", "seed-sql", "seed-mongo", "all"])
    args = parser.parse_args()

    if args.comando in ("init", "all"):
        pg = PostgresConnection()
        run_migrations(pg)
        pg.close()
        print("[OK] Migrations aplicadas.")

    if args.comando in ("seed-sql", "all"):
        seed_sql()

    if args.comando in ("seed-mongo", "all"):
        seed_mongo()


if __name__ == "__main__":
    main()
