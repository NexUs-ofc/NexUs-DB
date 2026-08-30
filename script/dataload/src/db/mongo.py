from pymongo import MongoClient
from ..config import get_env

class MongoConnection:
    def __init__(self):
        self.client = MongoClient(get_env("MONGO_URI"), serverSelectionTimeoutMS=10000)
        self.client.admin.command('ping')
        self.db = self.client[get_env("MONGO_DB")]

    def bulk_insert(self, collection: str, documents: list[dict]):
        if not documents:
            return
        result = self.db[collection].insert_many(documents)
        print(f"Foi inserido {len(result.inserted_ids)} documentos na collection '{collection}'.")
    def drop_collection(self, collection: str):
        self.db[collection].drop()
        print(f"Collection '{collection}' foi removida.")
    def close(self):
        if self.client:
            self.client.close()
