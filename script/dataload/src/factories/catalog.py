import random
from ..core.rng import get_faker
from ..core.schemas.catalog import Category, Food
from ..config import TAMANHOS
from ..seed import CATEGORIES

fake = get_faker()

def build_categories() -> list[Category]:
    return [Category(category_name=c) for c in CATEGORIES]


def build_food() -> list[Food]:
    foods = []
    for _ in range(TAMANHOS["food"]):
        foods.append(Food(
            name=fake.unique.ingredient().capitalize(),
            category_id=random.randint(1, len(CATEGORIES)),
            package_quantity=round(random.uniform(0.5, 20), 2),
            unit_of_measure=fake.random_element(elements=["g", "kg", "ml", "l", "unit"]),
            product_brand=fake.word().capitalize(),
        ))
    return foods
