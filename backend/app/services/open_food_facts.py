"""Open Food Facts API client for barcode lookup."""
import logging
from typing import Optional
from dataclasses import dataclass

import httpx

from app.config import get_settings
from app.schemas.nutrition import OpenFoodFactsProduct

logger = logging.getLogger(__name__)
settings = get_settings()


@dataclass
class NutrimentsPer100g:
    """Nutriments per 100g from Open Food Facts."""
    calories: Optional[float] = None
    protein: Optional[float] = None
    carbs: Optional[float] = None
    fat: Optional[float] = None
    fiber: Optional[float] = None
    sodium: Optional[float] = None
    sugar: Optional[float] = None
    saturated_fat: Optional[float] = None


class OpenFoodFactsClient:
    """Client for Open Food Facts API."""

    BASE_URL = "https://world.openfoodfacts.org/api/v2"

    def __init__(self, timeout: float = 10.0):
        """
        Initialize the client.

        Args:
            timeout: Request timeout in seconds
        """
        self.timeout = timeout
        self.headers = {
            "User-Agent": settings.off_user_agent,
            "Accept": "application/json",
        }

    async def get_product_by_barcode(
        self, barcode: str
    ) -> Optional[OpenFoodFactsProduct]:
        """
        Look up a product by barcode.

        Args:
            barcode: Product barcode (EAN/UPC)

        Returns:
            Product data or None if not found
        """
        url = f"{self.BASE_URL}/product/{barcode}.json"

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()

                if data.get("status") != 1:
                    logger.info(f"Product not found for barcode: {barcode}")
                    return None

                product = data.get("product", {})
                return self._parse_product(barcode, product)

            except httpx.HTTPError as e:
                logger.error(f"HTTP error fetching barcode {barcode}: {e}")
                return None
            except Exception as e:
                logger.error(f"Error fetching barcode {barcode}: {e}")
                return None

    async def search_products(
        self,
        query: str,
        page: int = 1,
        page_size: int = 20,
    ) -> list[OpenFoodFactsProduct]:
        """
        Search for products by name.

        Args:
            query: Search query
            page: Page number (1-indexed)
            page_size: Results per page

        Returns:
            List of matching products
        """
        url = f"{self.BASE_URL}/search"
        params = {
            "search_terms": query,
            "page": page,
            "page_size": page_size,
            "json": 1,
            "fields": "code,product_name,brands,nutriments,serving_size,serving_quantity,nutriscore_grade,nova_group,image_url",
        }

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            try:
                response = await client.get(url, params=params, headers=self.headers)
                response.raise_for_status()
                data = response.json()

                products = []
                for item in data.get("products", []):
                    barcode = item.get("code", "")
                    if barcode:
                        product = self._parse_product(barcode, item)
                        if product:
                            products.append(product)

                return products

            except httpx.HTTPError as e:
                logger.error(f"HTTP error searching products: {e}")
                return []
            except Exception as e:
                logger.error(f"Error searching products: {e}")
                return []

    def _parse_product(
        self, barcode: str, data: dict
    ) -> Optional[OpenFoodFactsProduct]:
        """
        Parse product data from API response.

        Args:
            barcode: Product barcode
            data: Raw product data from API

        Returns:
            Parsed product or None if essential data missing
        """
        name = data.get("product_name") or data.get("product_name_en", "")
        if not name:
            return None

        nutriments = data.get("nutriments", {})

        # Extract per 100g values
        calories = self._get_nutriment(nutriments, "energy-kcal_100g", "energy_100g")
        if calories and "energy_100g" in str(calories):
            # Convert from kJ to kcal if needed
            energy_kj = nutriments.get("energy_100g")
            if energy_kj:
                calories = energy_kj / 4.184

        protein = self._get_nutriment(nutriments, "proteins_100g")
        carbs = self._get_nutriment(nutriments, "carbohydrates_100g")
        fat = self._get_nutriment(nutriments, "fat_100g")
        fiber = self._get_nutriment(nutriments, "fiber_100g")
        sodium = self._get_nutriment(nutriments, "sodium_100g")
        sugar = self._get_nutriment(nutriments, "sugars_100g")
        saturated_fat = self._get_nutriment(nutriments, "saturated-fat_100g")

        # Sodium is often in mg, convert to mg if in g
        if sodium and sodium < 10:  # Likely in grams
            sodium = sodium * 1000

        # Parse serving size
        serving_size_g = None
        serving_description = data.get("serving_size")
        serving_quantity = data.get("serving_quantity")

        if serving_quantity:
            try:
                serving_size_g = float(serving_quantity)
            except (ValueError, TypeError):
                pass

        return OpenFoodFactsProduct(
            barcode=barcode,
            name=name,
            brand=data.get("brands"),
            image_url=data.get("image_url"),
            calories_per_100g=calories,
            protein_per_100g=protein,
            carbs_per_100g=carbs,
            fat_per_100g=fat,
            fiber_per_100g=fiber,
            sodium_per_100g=sodium,
            sugar_per_100g=sugar,
            saturated_fat_per_100g=saturated_fat,
            serving_size_g=serving_size_g,
            serving_description=serving_description,
            nutriscore_grade=data.get("nutriscore_grade"),
            nova_group=data.get("nova_group"),
            raw_data=data,
        )

    @staticmethod
    def _get_nutriment(
        nutriments: dict, *keys: str
    ) -> Optional[float]:
        """
        Get nutriment value from multiple possible keys.

        Args:
            nutriments: Nutriments dict
            keys: Possible keys to try

        Returns:
            Nutriment value or None
        """
        for key in keys:
            value = nutriments.get(key)
            if value is not None:
                try:
                    return float(value)
                except (ValueError, TypeError):
                    continue
        return None

    @staticmethod
    def calculate_for_serving(
        product: OpenFoodFactsProduct,
        grams: float,
    ) -> dict:
        """
        Calculate nutrition values for a specific serving size.

        Args:
            product: Product with per-100g values
            grams: Serving size in grams

        Returns:
            Dict with calculated values
        """
        multiplier = grams / 100.0

        return {
            "grams": grams,
            "calories": round((product.calories_per_100g or 0) * multiplier),
            "protein_g": round((product.protein_per_100g or 0) * multiplier, 1),
            "carbs_g": round((product.carbs_per_100g or 0) * multiplier, 1),
            "fat_g": round((product.fat_per_100g or 0) * multiplier, 1),
            "fiber_g": round((product.fiber_per_100g or 0) * multiplier, 1) if product.fiber_per_100g else None,
            "sodium_mg": round((product.sodium_per_100g or 0) * multiplier, 1) if product.sodium_per_100g else None,
            "sugar_g": round((product.sugar_per_100g or 0) * multiplier, 1) if product.sugar_per_100g else None,
        }


# Singleton instance
off_client = OpenFoodFactsClient()


async def lookup_barcode(barcode: str) -> Optional[OpenFoodFactsProduct]:
    """Convenience function to look up a barcode."""
    return await off_client.get_product_by_barcode(barcode)


async def search_foods(query: str, limit: int = 20) -> list[OpenFoodFactsProduct]:
    """Convenience function to search foods."""
    return await off_client.search_products(query, page_size=limit)
