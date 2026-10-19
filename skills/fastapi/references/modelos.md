# Modelos (SQLAlchemy 2.1 `Mapped`)

> Detalle de la sección **Modelos** de la skill `fastapi`: ejemplo de mapeo con SQLAlchemy sobre PostgreSQL. El diseño de esquema, tipos, índices, constraints y migraciones sigue la skill `sql`.

```python
# src/models/models.py
from datetime import datetime
from sqlalchemy import Integer, String, Boolean, ForeignKey, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from src.core.database import Base


class Category(Base):
  __tablename__ = "app_categories"

  id: Mapped[int] = mapped_column(Integer, primary_key=True)
  name: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)

  products: Mapped[list["Product"]] = relationship(back_populates="category")


class Product(Base):
  __tablename__ = "app_products"

  id: Mapped[int] = mapped_column(Integer, primary_key=True)
  category_id: Mapped[int] = mapped_column(Integer, ForeignKey("app_categories.id"), nullable=False)
  name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
  slug: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
  price: Mapped[int] = mapped_column(Integer, nullable=False)  # en centavos, nunca float
  is_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
  created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
  updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

  category: Mapped["Category"] = relationship(back_populates="products")
```
