import random

from ..config import TAMANHOS
from ..core.ids import RANGES
from ..core.rng import get_faker
from ..core.schemas.account import AuthMethod, Profile, ProfilePhone

fake = get_faker()


def build_profiles() -> list[Profile]:
    profiles = []
    for _ in range(len(RANGES["household"])):
        profiles.append(Profile(
            address_id=random.randint(1, TAMANHOS["address"]),
            email=fake.unique.email(),
            name=fake.name(),
            type="HOUSEHOLD",
        ))
    for _ in range(len(RANGES["company"])):
        profiles.append(Profile(
            address_id=random.randint(1, TAMANHOS["address"]),
            email=fake.unique.email(),
            name=fake.company(),
            type="COMPANY",
        ))
    for _ in range(len(RANGES["store"])):
        profiles.append(Profile(
            address_id=random.randint(1, TAMANHOS["address"]),
            email=fake.unique.email(),
            name=fake.company(),
            type="STORE",
        ))
    for _ in range(len(RANGES["admin"])):
        profiles.append(Profile(
            address_id=random.randint(1, TAMANHOS["address"]),
            email=fake.unique.email(),
            name=fake.name(),
            type="ADMIN",
        ))
    return profiles


def build_auth_methods() -> list[AuthMethod]:
    total = sum(len(r) for r in RANGES.values())
    return [
        AuthMethod(
            profile_id=pid,
            provider=fake.random_element(elements=["GOOGLE", "PASSWORD"]),
            credential=fake.uuid4(),
        )
        for pid in range(1, total + 1)
    ]


def build_profile_phones() -> list[ProfilePhone]:
    total = sum(len(r) for r in RANGES.values())
    result = []
    for pid in range(1, total + 1):
        for _ in range(random.randint(1, 2)):
            result.append(ProfilePhone(
                profile_id=pid,
                phone=fake.unique.msisdn(),
            ))
    return result
