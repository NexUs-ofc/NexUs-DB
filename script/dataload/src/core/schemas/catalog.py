from .base import BaseEntity
from typing import Optional
from dataclasses import dataclass

@dataclass(kw_only=True)
class Category(BaseEntity):
  category_name: str


@dataclass(kw_only=True)
class Food(BaseEntity):
  name: str
  category_id: int
  package_quantity: float
  unit_of_measure: str
  product_brand: Optional[str] = None
