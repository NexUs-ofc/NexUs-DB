from dataclasses import dataclass
from datetime import date

from .base import BaseEntity


@dataclass(kw_only=True)
class PantryItem(BaseEntity):
  food_id: int
  profile_id: int
  quantity: int
  expiry_date: date | None = None


@dataclass(kw_only=True)
class PantryProductSetting(BaseEntity):
  food_id: int
  profile_id: int
  minimum_quantity: int = 0
  updated_at: str | None = None
