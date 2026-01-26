"""Tests for the macro calculator service."""
import pytest

from app.services.macro_calculator import (
    MacroCalculator,
    calculate_macros,
    MacroTargets,
    ACTIVITY_MULTIPLIERS,
)
from app.models.user import Sex, ActivityLevel, GoalType


class TestBMRCalculation:
    """Tests for BMR calculation using Mifflin-St Jeor equation."""

    def test_bmr_male(self):
        """Test BMR calculation for male."""
        calculator = MacroCalculator()
        bmr = calculator.calculate_bmr(
            sex=Sex.MALE,
            weight_kg=80,
            height_cm=180,
            age=30,
        )
        # BMR = (10 × 80) + (6.25 × 180) - (5 × 30) + 5 = 800 + 1125 - 150 + 5 = 1780
        assert bmr == 1780

    def test_bmr_female(self):
        """Test BMR calculation for female."""
        calculator = MacroCalculator()
        bmr = calculator.calculate_bmr(
            sex=Sex.FEMALE,
            weight_kg=65,
            height_cm=165,
            age=28,
        )
        # BMR = (10 × 65) + (6.25 × 165) - (5 × 28) - 161 = 650 + 1031.25 - 140 - 161 = 1380
        assert bmr == 1380

    def test_bmr_edge_cases(self):
        """Test BMR with edge case values."""
        calculator = MacroCalculator()

        # Very light person
        bmr = calculator.calculate_bmr(Sex.FEMALE, 45, 150, 18)
        assert bmr > 0

        # Heavier person
        bmr = calculator.calculate_bmr(Sex.MALE, 120, 190, 45)
        assert bmr > 0


class TestTDEECalculation:
    """Tests for TDEE calculation."""

    def test_tdee_multipliers(self):
        """Test TDEE with different activity levels."""
        calculator = MacroCalculator()
        bmr = 1800

        for level, multiplier in ACTIVITY_MULTIPLIERS.items():
            tdee = calculator.calculate_tdee(bmr, level)
            expected = round(bmr * multiplier)
            assert tdee == expected, f"Failed for {level}"

    def test_tdee_sedentary(self):
        """Test TDEE for sedentary activity."""
        calculator = MacroCalculator()
        tdee = calculator.calculate_tdee(1800, ActivityLevel.SEDENTARY)
        assert tdee == 2160  # 1800 * 1.2

    def test_tdee_active(self):
        """Test TDEE for active activity level."""
        calculator = MacroCalculator()
        tdee = calculator.calculate_tdee(1800, ActivityLevel.ACTIVE)
        assert tdee == 3105  # 1800 * 1.725


class TestGoalCalories:
    """Tests for goal-based calorie calculation."""

    def test_maintenance_calories(self):
        """Test maintenance goal returns TDEE."""
        calculator = MacroCalculator()
        calories, adjustment = calculator.calculate_target_calories(
            tdee=2500,
            goal_type=GoalType.MAINTAIN,
            goal_rate_kg_per_week=0,
        )
        assert calories == 2500
        assert adjustment == 0

    def test_cut_calories(self):
        """Test cutting goal creates deficit."""
        calculator = MacroCalculator()
        calories, adjustment = calculator.calculate_target_calories(
            tdee=2500,
            goal_type=GoalType.CUT,
            goal_rate_kg_per_week=0.5,
        )
        # 7700 kcal/kg / 7 days * 0.5 kg/week = 550 deficit
        assert calories == 1950
        assert adjustment == -550

    def test_bulk_calories(self):
        """Test bulking goal creates surplus."""
        calculator = MacroCalculator()
        calories, adjustment = calculator.calculate_target_calories(
            tdee=2500,
            goal_type=GoalType.BULK,
            goal_rate_kg_per_week=0.5,
        )
        # Surplus is half the rate for lean gains
        # 7700 kcal/kg / 7 days * 0.5 * 0.5 = 275 surplus
        assert calories == 2775
        assert adjustment == 275

    def test_aggressive_cut_floor(self):
        """Test that aggressive cuts don't go below minimum."""
        calculator = MacroCalculator()
        calories, _ = calculator.calculate_target_calories(
            tdee=1500,  # Low TDEE
            goal_type=GoalType.CUT,
            goal_rate_kg_per_week=1.0,  # Aggressive
        )
        assert calories >= 1200  # Minimum safe calories


class TestMacroDistribution:
    """Tests for macro nutrient distribution."""

    def test_complete_macro_calculation(self):
        """Test complete macro calculation returns all values."""
        result = calculate_macros(
            sex=Sex.MALE,
            weight_kg=80,
            height_cm=180,
            age=30,
            activity_level=ActivityLevel.MODERATE,
            goal_type=GoalType.MAINTAIN,
        )

        assert isinstance(result, MacroTargets)
        assert result.calories > 0
        assert result.protein_g > 0
        assert result.carbs_g > 0
        assert result.fat_g > 0
        assert result.fiber_g > 0
        assert result.bmr > 0
        assert result.tdee > 0

    def test_protein_based_on_weight(self):
        """Test protein is calculated based on body weight."""
        calculator = MacroCalculator(protein_per_kg=2.0)
        result = calculator.calculate_macros(
            sex=Sex.MALE,
            weight_kg=80,
            height_cm=180,
            age=30,
            activity_level=ActivityLevel.MODERATE,
            goal_type=GoalType.MAINTAIN,
        )

        # 80kg * 2.0 g/kg = 160g protein
        assert result.protein_g == 160.0

    def test_fat_percentage(self):
        """Test fat is calculated as percentage of calories."""
        calculator = MacroCalculator(fat_percent=0.25)
        result = calculator.calculate_macros(
            sex=Sex.MALE,
            weight_kg=80,
            height_cm=180,
            age=30,
            activity_level=ActivityLevel.MODERATE,
            goal_type=GoalType.MAINTAIN,
        )

        # Fat should be ~25% of calories
        fat_calories = result.fat_g * 9
        fat_percent = fat_calories / result.calories
        assert 0.24 <= fat_percent <= 0.26

    def test_carbs_are_remainder(self):
        """Test carbs fill remaining calories after protein and fat."""
        result = calculate_macros(
            sex=Sex.MALE,
            weight_kg=80,
            height_cm=180,
            age=30,
            activity_level=ActivityLevel.MODERATE,
            goal_type=GoalType.MAINTAIN,
        )

        protein_cals = result.protein_g * 4
        fat_cals = result.fat_g * 9
        carb_cals = result.carbs_g * 4

        total_from_macros = protein_cals + fat_cals + carb_cals
        # Should be close to target calories
        assert abs(total_from_macros - result.calories) < 10

    def test_fiber_based_on_calories(self):
        """Test fiber is calculated based on calorie target."""
        result = calculate_macros(
            sex=Sex.MALE,
            weight_kg=80,
            height_cm=180,
            age=30,
            activity_level=ActivityLevel.MODERATE,
            goal_type=GoalType.MAINTAIN,
        )

        # 14g per 1000 calories
        expected_fiber = (result.calories / 1000) * 14
        assert abs(result.fiber_g - expected_fiber) < 1


class TestGoalRateValidation:
    """Tests for goal rate validation."""

    def test_valid_maintenance(self):
        """Test maintenance with zero rate is valid."""
        is_valid, warning = MacroCalculator.validate_goal_rate(GoalType.MAINTAIN, 0)
        assert is_valid
        assert warning is None

    def test_invalid_maintenance_with_rate(self):
        """Test maintenance with non-zero rate is invalid."""
        is_valid, warning = MacroCalculator.validate_goal_rate(GoalType.MAINTAIN, 0.5)
        assert not is_valid

    def test_valid_cut_rate(self):
        """Test reasonable cut rate is valid."""
        is_valid, warning = MacroCalculator.validate_goal_rate(GoalType.CUT, 0.5)
        assert is_valid
        assert warning is None

    def test_aggressive_cut_warning(self):
        """Test aggressive cut rate gives warning."""
        is_valid, warning = MacroCalculator.validate_goal_rate(GoalType.CUT, 0.8)
        assert is_valid
        assert warning is not None
        assert "aggressive" in warning.lower()

    def test_dangerous_cut_invalid(self):
        """Test dangerous cut rate is invalid."""
        is_valid, warning = MacroCalculator.validate_goal_rate(GoalType.CUT, 1.5)
        assert not is_valid

    def test_valid_bulk_rate(self):
        """Test reasonable bulk rate is valid."""
        is_valid, warning = MacroCalculator.validate_goal_rate(GoalType.BULK, 0.25)
        assert is_valid
        assert warning is None


class TestWeeksToGoal:
    """Tests for weeks to goal estimation."""

    def test_weight_loss_estimation(self):
        """Test weeks to goal for weight loss."""
        weeks = MacroCalculator.estimate_weeks_to_goal(
            current_weight_kg=90,
            target_weight_kg=80,
            rate_kg_per_week=0.5,
        )
        assert weeks == 20  # 10kg / 0.5kg per week

    def test_weight_gain_estimation(self):
        """Test weeks to goal for weight gain."""
        weeks = MacroCalculator.estimate_weeks_to_goal(
            current_weight_kg=70,
            target_weight_kg=75,
            rate_kg_per_week=0.25,
        )
        assert weeks == 20  # 5kg / 0.25kg per week

    def test_zero_rate_returns_none(self):
        """Test zero rate returns None."""
        weeks = MacroCalculator.estimate_weeks_to_goal(
            current_weight_kg=80,
            target_weight_kg=75,
            rate_kg_per_week=0,
        )
        assert weeks is None


class TestIntegration:
    """Integration tests for realistic scenarios."""

    def test_typical_male_cut(self):
        """Test typical male on a cut."""
        result = calculate_macros(
            sex=Sex.MALE,
            weight_kg=90,
            height_cm=180,
            age=30,
            activity_level=ActivityLevel.MODERATE,
            goal_type=GoalType.CUT,
            goal_rate_kg_per_week=0.5,
        )

        # Reasonable ranges for a cutting male
        assert 1800 <= result.calories <= 2500
        assert result.protein_g >= 140  # High protein for muscle retention
        assert result.deficit_or_surplus < 0

    def test_typical_female_maintain(self):
        """Test typical female on maintenance."""
        result = calculate_macros(
            sex=Sex.FEMALE,
            weight_kg=65,
            height_cm=165,
            age=28,
            activity_level=ActivityLevel.LIGHT,
            goal_type=GoalType.MAINTAIN,
        )

        # Reasonable ranges for a maintaining female
        assert 1600 <= result.calories <= 2200
        assert result.deficit_or_surplus == 0

    def test_active_athlete_bulk(self):
        """Test active athlete on a lean bulk."""
        result = calculate_macros(
            sex=Sex.MALE,
            weight_kg=75,
            height_cm=178,
            age=25,
            activity_level=ActivityLevel.VERY_ACTIVE,
            goal_type=GoalType.BULK,
            goal_rate_kg_per_week=0.25,
        )

        # High calories and protein for active bulking
        assert result.calories >= 3000
        assert result.protein_g >= 120
        assert result.deficit_or_surplus > 0
