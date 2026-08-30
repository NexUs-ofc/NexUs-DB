import re
from ..core.rng import get_faker
from ..core.schemas.address import Address
from ..config import TAMANHOS

fake = get_faker()


def build_addresses() -> list[Address]:
    result = []
    for _ in range(TAMANHOS["address"]):
        result.append(Address(
            neighborhood=fake.neighborhood(),
            street=fake.street_name(),
            number=fake.building_number(),
            cep=fake.postcode().replace('-', '').replace('.', ''),
            city=fake.city(),
            state=fake.state_abbr().upper(),
        ))
    return result
