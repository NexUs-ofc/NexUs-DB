import os

from dotenv import load_dotenv

from .core.ids import TOTAL_PROFILES

load_dotenv()

TAMANHOS = {
    "categoria": 8,
    "food": 40,
    "address": 50,
    "profile": TOTAL_PROFILES,
    "auth_method": TOTAL_PROFILES,
    "plan": 3,
    "company": 10,
    "store": 10,
    "payment": 30,
    "pantry_item": 150,
    "pantry_product_setting": 120,
    "recipe": 30,
    "event": 40,
    "recipe_account": 30,
    "conversation": 40,
    "knowledge": 30,
    "record": 60,
    "shopping_list": 40,
    "metric": 20,
    "tool_metric": 30,
    "trace": 20
}

SEED = 83290473298748365874366576345734

def get_env(key: str) -> str:
    value = os.getenv(key)
    if value is None:
        raise ValueError(f"Variavel de ambiente '{key}' não encontrada.")
    return value
