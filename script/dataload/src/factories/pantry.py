import random

from ..config import TAMANHOS
from ..core.ids import RANGES
from ..core.rng import get_faker
from ..core.schemas.pantry import PantryItem

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
