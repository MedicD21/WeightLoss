"""Macro nutrient calculator using Mifflin-St Jeor equation."""
from dataclasses import dataclass
from enum import Enum
from typing import Optional

from app.models.user import Sex, ActivityLevel, GoalType


# Activity level multipliers for TDEE calculation
ACTIVITY_MULTIPLIERS = {
    ActivityLevel.SEDENTARY: 1.2,      # Little or no exercise
    ActivityLevel.LIGHT: 1.375,         # Light exercise 1-3 days/week
    ActivityLevel.MODERATE: 1.55,       # Moderate exercise 3-5 days/week
    ActivityLevel.ACTIVE: 1.725,        # Hard exercise 6-7 days/week
    ActivityLevel.VERY_ACTIVE: 1.9,     # Very hard exercise, physical job
}

# Calories per kg of body weight change
# ~7700 kcal per kg of fat
CALORIES_PER_KG = 7700

# Default macro ratios
DEFAULT_PROTEIN_PER_KG = 1.8  # grams per kg body weight
MIN_PROTEIN_PERCENT = 0.10   # Minimum 10% of calories from protein
FAT_PERCENT = 0.25           # 25% of calories from fat
FIBER_PER_1000_KCAL = 14     # grams per 1000 calories


@dataclass
class MacroTargets:
    """Calculated macro nutrient targets."""
    calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: Optional[float]
    bmr: int
    tdee: int
    deficit_or_surplus: int


class MacroCalculator:
    """
    Calculator for macro nutrient targets based on body metrics and goals.

    Uses the Mifflin-St Jeor equation for BMR calculation:
    - Male:   BMR = (10 × weight_kg) + (6.25 × height_cm) - (5 × age) + 5
    - Female: BMR = (10 × weight_kg) + (6.25 × height_cm) - (5 × age) - 161
    """

    def __init__(
        self,
        protein_per_kg: float = DEFAULT_PROTEIN_PER_KG,
        fat_percent: float = FAT_PERCENT,
        fiber_per_1000_kcal: float = FIBER_PER_1000_KCAL,
    ):
        """
        Initialize calculator with configurable parameters.

        Args:
            protein_per_kg: Grams of protein per kg body weight (default 1.8)
            fat_percent: Percentage of calories from fat (default 0.25)
            fiber_per_1000_kcal: Grams of fiber per 1000 calories (default 14)
        """
        self.protein_per_kg = protein_per_kg
        self.fat_percent = fat_percent
        self.fiber_per_1000_kcal = fiber_per_1000_kcal

    def calculate_bmr(
        self,
        sex: Sex,
        weight_kg: float,
        height_cm: float,
        age: int,
    ) -> int:
        """
        Calculate Basal Metabolic Rate using Mifflin-St Jeor equation.

        Args:
            sex: Biological sex (male/female)
            weight_kg: Body weight in kilograms
            height_cm: Height in centimeters
            age: Age in years

        Returns:
            BMR in calories per day
        """
        bmr = (10 * weight_kg) + (6.25 * height_cm) - (5 * age)

        if sex == Sex.MALE:
            bmr += 5
        else:
            bmr -= 161

        return round(bmr)

    def calculate_tdee(self, bmr: int, activity_level: ActivityLevel) -> int:
        """
        Calculate Total Daily Energy Expenditure.

        Args:
            bmr: Basal Metabolic Rate
            activity_level: Activity level for multiplier

        Returns:
            TDEE in calories per day
        """
        multiplier = ACTIVITY_MULTIPLIERS.get(activity_level, 1.55)
        return round(bmr * multiplier)

    def calculate_target_calories(
        self,
        tdee: int,
        goal_type: GoalType,
        goal_rate_kg_per_week: float = 0.5,
    ) -> tuple[int, int]:
        """
        Calculate target calories based on goal.

        Args:
            tdee: Total Daily Energy Expenditure
            goal_type: Goal type (cut/maintain/bulk)
            goal_rate_kg_per_week: Rate of weight change per week

        Returns:
            Tuple of (target_calories, deficit_or_surplus)
        """
        if goal_type == GoalType.MAINTAIN:
            return tdee, 0

        # Calculate daily calorie adjustment
        # CALORIES_PER_KG / 7 days = calories per day per kg/week
        daily_adjustment = round((CALORIES_PER_KG / 7) * goal_rate_kg_per_week)

        if goal_type == GoalType.CUT:
            # Deficit for weight loss
            target = tdee - daily_adjustment
            # Ensure minimum safe calories (BMR is a rough floor)
            target = max(target, 1200)  # Absolute minimum
            return target, -daily_adjustment
        else:
            # Surplus for weight gain (slower, as advised)
            # Use half the rate for bulking to minimize fat gain
            surplus = round(daily_adjustment * 0.5)
            return tdee + surplus, surplus

    def calculate_macros(
        self,
        sex: Sex,
        weight_kg: float,
        height_cm: float,
        age: int,
        activity_level: ActivityLevel,
        goal_type: GoalType,
        goal_rate_kg_per_week: float = 0.5,
        protein_per_kg: Optional[float] = None,
    ) -> MacroTargets:
        """
        Calculate complete macro nutrient targets.

        Args:
            sex: Biological sex
            weight_kg: Body weight in kg
            height_cm: Height in cm
            age: Age in years
            activity_level: Activity level
            goal_type: Fitness goal
            goal_rate_kg_per_week: Rate of weight change
            protein_per_kg: Optional override for protein ratio

        Returns:
            MacroTargets with all calculated values
        """
        # Use instance default or override
        protein_ratio = protein_per_kg or self.protein_per_kg

        # Calculate base metabolic values
        bmr = self.calculate_bmr(sex, weight_kg, height_cm, age)
        tdee = self.calculate_tdee(bmr, activity_level)
        target_calories, adjustment = self.calculate_target_calories(
            tdee, goal_type, goal_rate_kg_per_week
        )

        # Calculate protein (based on body weight)
        protein_g = round(weight_kg * protein_ratio, 1)
        protein_calories = protein_g * 4

        # Ensure minimum protein percentage
        min_protein_calories = target_calories * MIN_PROTEIN_PERCENT
        if protein_calories < min_protein_calories:
            protein_g = round(min_protein_calories / 4, 1)
            protein_calories = protein_g * 4

        # Calculate fat (percentage of total calories)
        fat_calories = target_calories * self.fat_percent
        fat_g = round(fat_calories / 9, 1)

        # Calculate carbs (remaining calories)
        remaining_calories = target_calories - protein_calories - fat_calories
        carbs_g = round(max(remaining_calories / 4, 0), 1)

        # Calculate fiber (based on calorie target)
        fiber_g = round((target_calories / 1000) * self.fiber_per_1000_kcal, 1)

        return MacroTargets(
            calories=target_calories,
            protein_g=protein_g,
            carbs_g=carbs_g,
            fat_g=fat_g,
            fiber_g=fiber_g,
            bmr=bmr,
            tdee=tdee,
            deficit_or_surplus=adjustment,
        )

    @staticmethod
    def estimate_weeks_to_goal(
        current_weight_kg: float,
        target_weight_kg: float,
        rate_kg_per_week: float,
    ) -> Optional[int]:
        """
        Estimate weeks to reach target weight.

        Args:
            current_weight_kg: Current weight
            target_weight_kg: Target weight
            rate_kg_per_week: Rate of weight change

        Returns:
            Estimated weeks, or None if invalid
        """
        if rate_kg_per_week <= 0:
            return None

        difference = abs(current_weight_kg - target_weight_kg)
        return round(difference / rate_kg_per_week)

    @staticmethod
    def validate_goal_rate(
        goal_type: GoalType,
        rate_kg_per_week: float,
    ) -> tuple[bool, Optional[str]]:
        """
        Validate that goal rate is safe and realistic.

        Args:
            goal_type: The goal type
            rate_kg_per_week: Proposed rate

        Returns:
            Tuple of (is_valid, warning_message)
        """
        if goal_type == GoalType.MAINTAIN:
            if rate_kg_per_week != 0:
                return False, "Rate should be 0 for maintenance goal"
            return True, None

        if rate_kg_per_week < 0:
            return False, "Rate must be positive"

        if goal_type == GoalType.CUT:
            if rate_kg_per_week > 1.0:
                return False, "Losing more than 1kg/week is not recommended for health"
            if rate_kg_per_week > 0.75:
                return True, "This is an aggressive deficit. Consider 0.5kg/week for sustainability"

        elif goal_type == GoalType.BULK:
            if rate_kg_per_week > 0.5:
                return False, "Gaining more than 0.5kg/week will likely result in excess fat gain"
            if rate_kg_per_week > 0.25:
                return True, "Consider a slower bulk (0.25kg/week) to minimize fat gain"

        return True, None


# Singleton instance for convenience
default_calculator = MacroCalculator()


def calculate_macros(
    sex: Sex,
    weight_kg: float,
    height_cm: float,
    age: int,
    activity_level: ActivityLevel,
    goal_type: GoalType,
    goal_rate_kg_per_week: float = 0.5,
    protein_per_kg: Optional[float] = None,
) -> MacroTargets:
    """Convenience function using default calculator."""
    return default_calculator.calculate_macros(
        sex=sex,
        weight_kg=weight_kg,
        height_cm=height_cm,
        age=age,
        activity_level=activity_level,
        goal_type=goal_type,
        goal_rate_kg_per_week=goal_rate_kg_per_week,
        protein_per_kg=protein_per_kg,
    )
