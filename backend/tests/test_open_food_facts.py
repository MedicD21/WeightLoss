"""Tests for Open Food Facts parsing logic."""
import pytest

from app.services.open_food_facts import OpenFoodFactsClient


def test_energy_kj_converts_to_kcal():
    client = OpenFoodFactsClient()
    data = {
        "product_name": "Test Product",
        "nutriments": {
            "energy_100g": 418.4,  # 100 kcal
        },
    }

    product = client._parse_product("123456", data)

    assert product is not None
    assert product.calories_per_100g == pytest.approx(100.0, rel=1e-3)


def test_energy_kcal_takes_precedence_over_kj():
    client = OpenFoodFactsClient()
    data = {
        "product_name": "Test Product",
        "nutriments": {
            "energy-kcal_100g": 90,
            "energy_100g": 500,  # Should be ignored when kcal is present
        },
    }

    product = client._parse_product("123456", data)

    assert product is not None
    assert product.calories_per_100g == 90
