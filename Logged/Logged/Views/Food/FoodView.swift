import SwiftUI
import SwiftData

/// Food tracking view
struct FoodView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meal.timestamp, order: .reverse) private var recentMeals: [Meal]

    @State private var showingAddMeal = false
    @State private var showingBarcodeScan = false
    @State private var showingPhotoCapture = false
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Date picker
                    DateSelector(selectedDate: $selectedDate)

                    // Daily summary
                    DailyNutritionSummary(meals: mealsForSelectedDate)

                    // Add options
                    AddFoodOptions(
                        onManualAdd: { showingAddMeal = true },
                        onBarcodeScan: { showingBarcodeScan = true },
                        onPhotoCapture: { showingPhotoCapture = true }
                    )

                    // Meals list
                    MealsListSection(
                        meals: mealsForSelectedDate,
                        onDelete: deleteMeal
                    )
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Food")
            .sheet(isPresented: $showingAddMeal) {
                AddMealView(date: selectedDate)
            }
            .sheet(isPresented: $showingBarcodeScan) {
                BarcodeScannerView()
            }
            .sheet(isPresented: $showingPhotoCapture) {
                FoodPhotoView()
            }
        }
    }

    private var mealsForSelectedDate: [Meal] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return recentMeals.filter { meal in
            meal.timestamp >= startOfDay && meal.timestamp < endOfDay
        }
    }

    private func deleteMeal(_ meal: Meal) {
        modelContext.delete(meal)
    }
}

// MARK: - Date Selector

struct DateSelector: View {
    @Binding var selectedDate: Date

    var body: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(Theme.Colors.accent)
            }

            Spacer()

            Button {
                // Show date picker
            } label: {
                VStack(spacing: 2) {
                    Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)

                    if Calendar.current.isDateInToday(selectedDate) {
                        Text("Today")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.accent)
                    }
                }
            }

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(
                        Calendar.current.isDateInToday(selectedDate)
                            ? Theme.Colors.textTertiary
                            : Theme.Colors.accent
                    )
            }
            .disabled(Calendar.current.isDateInToday(selectedDate))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }
}

// MARK: - Daily Nutrition Summary

struct DailyNutritionSummary: View {
    let meals: [Meal]

    var totalCalories: Int {
        meals.reduce(0) { $0 + $1.totalCalories }
    }

    var totalProtein: Double {
        meals.reduce(0) { $0 + $1.totalProteinG }
    }

    var totalCarbs: Double {
        meals.reduce(0) { $0 + $1.totalCarbsG }
    }

    var totalFat: Double {
        meals.reduce(0) { $0 + $1.totalFatG }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("Total")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("\(totalCalories) cal")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.calories)
            }

            HStack(spacing: Theme.Spacing.lg) {
                MacroSummaryItem(name: "Protein", value: totalProtein, color: Theme.Colors.protein)
                MacroSummaryItem(name: "Carbs", value: totalCarbs, color: Theme.Colors.carbs)
                MacroSummaryItem(name: "Fat", value: totalFat, color: Theme.Colors.fat)
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct MacroSummaryItem: View {
    let name: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text(String(format: "%.0fg", value))
                .font(Theme.Typography.headline)
                .foregroundColor(color)
            Text(name)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Add Food Options

struct AddFoodOptions: View {
    let onManualAdd: () -> Void
    let onBarcodeScan: () -> Void
    let onPhotoCapture: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            AddOptionButton(
                icon: "plus.circle.fill",
                title: "Manual",
                color: Theme.Colors.accent,
                action: onManualAdd
            )

            AddOptionButton(
                icon: "barcode.viewfinder",
                title: "Scan",
                color: Theme.Colors.info,
                action: onBarcodeScan
            )

            AddOptionButton(
                icon: "camera.fill",
                title: "Photo",
                color: Theme.Colors.warning,
                action: onPhotoCapture
            )
        }
    }
}

struct AddOptionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)

                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .cardStyle()
        }
    }
}

// MARK: - Meals List

struct MealsListSection: View {
    let meals: [Meal]
    let onDelete: (Meal) -> Void

    var groupedMeals: [(MealType, [Meal])] {
        let grouped = Dictionary(grouping: meals) { $0.mealType }
        return MealType.allCases.compactMap { type in
            guard let meals = grouped[type], !meals.isEmpty else { return nil }
            return (type, meals.sorted { $0.timestamp < $1.timestamp })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if meals.isEmpty {
                EmptyMealsView()
            } else {
                ForEach(groupedMeals, id: \.0) { mealType, meals in
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Image(systemName: mealType.icon)
                                .foregroundColor(Theme.Colors.accent)
                            Text(mealType.displayName)
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }

                        ForEach(meals) { meal in
                            MealCard(meal: meal, onDelete: { onDelete(meal) })
                        }
                    }
                }
            }
        }
    }
}

struct MealCard: View {
    let meal: Meal
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(meal.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Text("\(meal.totalCalories) cal")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.calories)
            }

            HStack(spacing: Theme.Spacing.md) {
                MacroLabel(value: meal.totalProteinG, unit: "P", color: Theme.Colors.protein)
                MacroLabel(value: meal.totalCarbsG, unit: "C", color: Theme.Colors.carbs)
                MacroLabel(value: meal.totalFatG, unit: "F", color: Theme.Colors.fat)

                Spacer()

                Text(meal.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            if !meal.items.isEmpty {
                Text(meal.items.map { $0.name }.joined(separator: ", "))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct MacroLabel: View {
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(String(format: "%.0f", value))
                .font(Theme.Typography.caption)
                .foregroundColor(color)
            Text(unit)
                .font(Theme.Typography.caption2)
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }
}

struct EmptyMealsView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "fork.knife")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("No meals logged")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textSecondary)

            Text("Add your first meal to start tracking")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }
}

// MARK: - Placeholder Views

struct AddMealView: View {
    let date: Date
    var onSaved: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]
    @Environment(\.dismiss) private var dismiss

    @State private var mealName = ""
    @State private var mealType: MealType = .breakfast
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var gramsText = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Meal name", text: $mealName)

                    Picker("Type", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    TextField("Notes (optional)", text: $notes)
                }

                Section("Nutrition") {
                    HStack {
                        TextField("Calories", text: $caloriesText)
                            .keyboardType(.numberPad)
                        Text("cal")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    HStack {
                        TextField("Protein", text: $proteinText)
                            .keyboardType(.decimalPad)
                        Text("g")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    HStack {
                        TextField("Carbs", text: $carbsText)
                            .keyboardType(.decimalPad)
                        Text("g")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    HStack {
                        TextField("Fat", text: $fatText)
                            .keyboardType(.decimalPad)
                        Text("g")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    HStack {
                        TextField("Serving size", text: $gramsText)
                            .keyboardType(.decimalPad)
                        Text("g")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }
            }
            .navigationTitle("Add Meal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveMeal() }
                        .disabled(mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveMeal() {
        let trimmedName = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Meal name is required."
            return
        }

        let calories = Int(caloriesText) ?? 0
        let protein = Double(proteinText) ?? 0
        let carbs = Double(carbsText) ?? 0
        let fat = Double(fatText) ?? 0
        let grams = Double(gramsText) ?? 100

        let profile = getOrCreateProfile()
        let meal = Meal(
            userId: profile.id,
            name: trimmedName,
            mealType: mealType,
            timestamp: date,
            notes: notes.isEmpty ? nil : notes
        )

        let item = FoodItem(
            name: trimmedName,
            source: .manual,
            grams: grams,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat
        )
        item.meal = meal
        meal.addItem(item)

        modelContext.insert(meal)
        modelContext.insert(item)

        onSaved?()
        dismiss()
    }

    private func getOrCreateProfile() -> UserProfile {
        if let profile = userProfiles.first {
            return profile
        }
        let profile = UserProfile(email: "user@example.com")
        modelContext.insert(profile)
        return profile
    }
}

struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Barcode Scanner")
                .navigationTitle("Scan Barcode")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

struct FoodPhotoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Food Photo Analysis")
                .navigationTitle("Photo")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    FoodView()
        .environmentObject(AppState())
        .modelContainer(for: [Meal.self])
}
