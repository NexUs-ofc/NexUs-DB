from .base import BaseEntity
from dataclasses import dataclass

@dataclass(kw_only=True)
class Address(BaseEntity):
  neighborhood: str
  street: str
  number: str
  cep: str
  city: str
  state: str
