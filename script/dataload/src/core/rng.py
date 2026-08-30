from faker import Faker
from faker_food import FoodProvider
from ..config import SEED
import random

fake = Faker("pt-BR")
fake.add_provider(FoodProvider)
Faker.seed(SEED)
random.seed(1)

def get_faker() -> Faker:
    return fake
