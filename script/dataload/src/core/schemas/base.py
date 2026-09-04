from dataclasses import dataclass
from datetime import datetime


@dataclass
class BaseEntity:
    id: int | None = None
    created_at: datetime | None = None

    def to_dict(self) -> dict:
        resultado = {}
        for k, v in self.__dict__.items():
            if v is not None:
                resultado[k] = v
        return resultado



