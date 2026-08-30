from .base import BaseEntity
from typing import Optional
from dataclasses import dataclass

@dataclass(kw_only=True)
class Profile(BaseEntity):
  address_id: int
  email: str
  name: str
  type: str
  status: str = "ACTIVE"
  profile_image_url: Optional[str] = None


@dataclass(kw_only=True)
class ProfilePhone(BaseEntity):
  profile_id: int
  phone: str


@dataclass(kw_only=True)
class AuthMethod(BaseEntity):
  profile_id: int
  provider: str
  credential: str
