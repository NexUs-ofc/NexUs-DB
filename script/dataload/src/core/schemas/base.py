from typing import Optional
from datetime import datetime
from dataclasses import dataclass

@dataclass
class BaseEntity:
    id: Optional[int] = None
    created_at: Optional[datetime] = None

    def to_dict(self) -> dict:
        resultado = {}
        for k, v in self.__dict__.items():
            if v is not None:
                resultado[k] = v
        return resultado



