import argparse

from .db.mongo import MongoConnection
from .db.postgres import PostgresConnection
from .seeders import mongo_seeder, postgres_seeder


def seed_sql():
    pg = PostgresConnection()
    try:
        postgres_seeder.run(pg)
    finally:
        pg.close()
    print("[OK] PostgreSQL populado.")


def seed_mongo():
    mongo = MongoConnection()
    try:
        mongo_seeder.run(mongo)
    finally:
        mongo.close()
    print("[OK] MongoDB populado.")


def main():
    parser = argparse.ArgumentParser(description="NexUs-DB dataload")
    parser.add_argument("comando", choices=["seed-sql", "seed-mongo", "all"])
    args = parser.parse_args()

    if args.comando in ("seed-sql", "all"):
        seed_sql()

    if args.comando in ("seed-mongo", "all"):
        seed_mongo()


if __name__ == "__main__":
    main()
