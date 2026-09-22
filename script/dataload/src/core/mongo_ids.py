from bson import ObjectId

from ..config import TAMANHOS

RECIPE_OIDS: list[ObjectId] = []
EVENT_OIDS: list[ObjectId] = []


def regenerate_mongo_ids():
    RECIPE_OIDS[:] = [ObjectId() for _ in range(TAMANHOS["recipe"])]
    EVENT_OIDS[:] = [ObjectId() for _ in range(TAMANHOS["event"])]


regenerate_mongo_ids()
