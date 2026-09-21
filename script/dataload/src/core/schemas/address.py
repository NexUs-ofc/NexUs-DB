from dataclasses import dataclass
from decimal import Decimal

from .base import BaseEntity


@dataclass(kw_only=True)
class Address(BaseEntity):
    neighborhood: str
    street: str
    number: str
    cep: str
    city: str
    state: str
    latitude: Decimal | None = None
    longitude: Decimal | None = None
