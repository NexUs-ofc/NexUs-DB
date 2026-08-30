from bson import ObjectId
from ..config import TAMANHOS

RECIPE_OIDS = [ObjectId(f"{i:024x}") for i in range(1, TAMANHOS["recipe"] + 1)]
EVENT_OIDS = [ObjectId(f"{i:024x}") for i in range(1, TAMANHOS["event"] + 1)]
