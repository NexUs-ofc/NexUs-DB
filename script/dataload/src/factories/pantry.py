import random
import itertools
from ..core.rng import get_faker
from ..core.schemas.pantry import PantryItem, PantryProductSetting
from ..core.ids import RANGES
from ..config import TAMANHOS

fake = get_faker()


def build_pantry_items() -> list[PantryItem]:
    return [
        PantryItem(
            food_id=random.randint(1, TAMANHOS["food"]),
            profile_id=random.choice(list(RANGES["household"])),
            quantity=random.randint(1, 20),
            expiry_date=fake.date_between(start_date="today", end_date="+180d"),
        )
        for _ in range(TAMANHOS["pantry_item"])
    ]


def build_pantry_product_setting(food_count: int) -> list[PantryProductSetting]:
    combinacoes = list(itertools.product(
        RANGES["household"],
        range(1, food_count + 1),
    ))
    if len(combinacoes) < TAMANHOS["pantry_product_setting"]:
        raise ValueError("Nao ha combinacoes suficientes (household x food).")

    pares = random.sample(combinacoes, TAMANHOS["pantry_product_setting"])

    return [
        PantryProductSetting(
            profile_id=profile_id,
            food_id=food_id,
            minimum_quantity=random.randint(0, 10),
        )
        for profile_id, food_id in pares
    ]
