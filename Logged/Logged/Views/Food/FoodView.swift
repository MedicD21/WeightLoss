import SwiftUI
import SwiftData
import AVFoundation
import Photos
import PhotosUI
import UIKit

/// Food tracking view
struct FoodView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meal.timestamp, order: .reverse) private var recentMeals: [Meal]

    @State private var showingAddMeal = false
    @State private var showingBarcodeScan = false
    @State private var showingPhotoCapture = false
    @State private var editingMeal: Meal?
    @State private var selectedDate = Date()
    @State private var syncError: String?
    @State private var toastMessage: String?
    @State private var isSyncing = false

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
                        onEdit: { meal in editingMeal = meal },
                        onDelete: deleteMeal
                    )

                    if let syncError {
                        Text(syncError)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Color.clear)
            .navigationTitle("Food")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            _ = await syncMeals(for: selectedDate, showToast: true)
                        }
                    } label: {
                        Label("Sync", systemImage: "arrow.clockwise")
                    }
                    .disabled(isSyncing)
                }
            }
            .sheet(isPresented: $showingAddMeal) {
                AddMealView(date: selectedDate)
            }
            .sheet(isPresented: $showingBarcodeScan) {
                BarcodeScannerView()
            }
            .sheet(isPresented: $showingPhotoCapture) {
                FoodPhotoView()
            }
            .sheet(item: $editingMeal) { meal in
                EditMealView(meal: meal)
            }
            .task {
                _ = await syncMeals(for: selectedDate)
            }
            .onChange(of: selectedDate) { _, newValue in
                Task {
                    _ = await syncMeals(for: newValue)
                }
            }
            .overlay(alignment: .top) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.surfaceHighlight)
                        .cornerRadius(Theme.Radius.medium)
                        .padding(.top, Theme.Spacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
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
        Task {
            do {
                try await APIService.shared.deleteMeal(id: meal.id)
                await MainActor.run {
                    modelContext.delete(meal)
                    try? modelContext.save()
                }
            } catch {
                await MainActor.run {
                    syncError = error.localizedDescription
                }
            }
        }
    }

    private func syncMeals(for date: Date, showToast: Bool = false) async -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        do {
            await MainActor.run {
                isSyncing = true
            }
            let summaries = try await APIService.shared.listMealSummaries(startDate: startOfDay, endDate: endOfDay)
            var responses: [MealResponseDTO] = []
            for summary in summaries {
                let response = try await APIService.shared.fetchMeal(id: summary.id)
                responses.append(response)
            }

            await MainActor.run {
                for meal in recentMeals where meal.timestamp >= startOfDay && meal.timestamp < endOfDay {
                    modelContext.delete(meal)
                }
                for response in responses {
                    upsertMeal(response, modelContext: modelContext)
                }
                try? modelContext.save()
                syncError = nil
                isSyncing = false
                if showToast {
                    showToastMessage("Sync complete")
                }
            }
            return true
        } catch {
            await MainActor.run {
                syncError = error.localizedDescription
                isSyncing = false
            }
            return false
        }
    }

    private func showToastMessage(_ message: String) {
        withAnimation {
            toastMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation {
                toastMessage = nil
            }
        }
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
    let onEdit: (Meal) -> Void
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
                            MealCard(
                                meal: meal,
                                onEdit: { onEdit(meal) },
                                onDelete: { onDelete(meal) }
                            )
                        }
                    }
                }
            }
        }
    }
}

struct MealCard: View {
    let meal: Meal
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(meal.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                if let grade = meal.items.first(where: { ($0.nutriScoreGrade ?? "").isEmpty == false })?.nutriScoreGrade {
                    NutriScoreBadge(grade: grade)
                }

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
                Text(meal.items.map { itemDisplayName($0) }.joined(separator: ", "))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Theme.Colors.accent)
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func itemDisplayName(_ item: FoodItem) -> String {
        if let grade = item.nutriScoreGrade, !grade.isEmpty {
            return "\(item.name) (\(grade.uppercased()))"
        }
        return item.name
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
    @State private var isSaving = false

    // Food search state
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [OFFProduct] = []
    @State private var showManualEntry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    // Meal type picker
                    Picker("Type", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Spacing.md)

                    // Food search section
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Search Food Database")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.md)

                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(Theme.Colors.textSecondary)

                            TextField("Search foods...", text: $searchText)
                                .textInputAutocapitalization(.none)
                                .disableAutocorrection(true)
                                .onSubmit { performSearch() }

                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.surface)
                        .cornerRadius(Theme.Radius.medium)
                        .padding(.horizontal, Theme.Spacing.md)

                        // Search results or loading indicator
                        if isSearching {
                            VStack(spacing: Theme.Spacing.md) {
                                ProgressView()
                                    .tint(Theme.Colors.accent)
                                Text("Searching...")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xl)
                        } else if !searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("\(searchResults.count) Results")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .padding(.horizontal, Theme.Spacing.md)

                                ForEach(searchResults, id: \.code) { product in
                                    Button(action: { selectFood(product) }) {
                                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                            Text(product.name)
                                                .font(Theme.Typography.headline)
                                                .foregroundColor(Theme.Colors.textPrimary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)

                                            HStack(spacing: Theme.Spacing.md) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Calories")
                                                        .font(Theme.Typography.caption2)
                                                        .foregroundColor(Theme.Colors.textSecondary)
                                                    Text("\(product.caloriesPer100g ?? 0) kcal")
                                                        .font(Theme.Typography.callout)
                                                        .foregroundColor(Theme.Colors.calories)
                                                }

                                                Divider()
                                                    .frame(height: 30)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Protein")
                                                        .font(Theme.Typography.caption2)
                                                        .foregroundColor(Theme.Colors.textSecondary)
                                                    Text("\(String(format: "%.1f", product.proteinPer100g ?? 0))g")
                                                        .font(Theme.Typography.callout)
                                                        .foregroundColor(Theme.Colors.protein)
                                                }

                                                Spacer()
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, Theme.Spacing.sm)
                                        .padding(.horizontal, Theme.Spacing.md)
                                        .background(Theme.Colors.surface)
                                        .cornerRadius(Theme.Radius.medium)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        } else if !searchText.isEmpty && !isSearching {
                            Text("No results found")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.lg)
                        }
                    }

                    if !searchResults.isEmpty || showManualEntry {
                        Divider()
                            .padding(.vertical, Theme.Spacing.sm)
                    }

                    // Manual entry section
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if searchResults.isEmpty && !searchText.isEmpty {
                            Text("Or Create Your Own")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.md)
                        } else if !showManualEntry && searchResults.isEmpty {
                            Button(action: { showManualEntry = true }) {
                                HStack {
                                    Text("+ Manual Entry")
                                        .font(Theme.Typography.subheadline)
                                        .foregroundColor(Theme.Colors.accent)
                                    Spacer()
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }

                        if showManualEntry || searchResults.isEmpty && searchText.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    Text("Meal Name")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                    TextField("Meal name", text: $mealName)
                                        .padding(.vertical, Theme.Spacing.xs)
                                        .padding(.horizontal, Theme.Spacing.sm)
                                        .background(Theme.Colors.surface)
                                        .cornerRadius(Theme.Radius.medium)
                                }

                                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    Text("Nutrition")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)

                                    HStack {
                                        TextField("Calories", text: $caloriesText)
                                            .keyboardType(.numberPad)
                                        Text("cal").foregroundColor(Theme.Colors.textSecondary)
                                    }
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .background(Theme.Colors.surface)
                                    .cornerRadius(Theme.Radius.medium)

                                    HStack {
                                        TextField("Protein", text: $proteinText)
                                            .keyboardType(.decimalPad)
                                        Text("g").foregroundColor(Theme.Colors.textSecondary)
                                    }
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .background(Theme.Colors.surface)
                                    .cornerRadius(Theme.Radius.medium)

                                    HStack {
                                        TextField("Carbs", text: $carbsText)
                                            .keyboardType(.decimalPad)
                                        Text("g").foregroundColor(Theme.Colors.textSecondary)
                                    }
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .background(Theme.Colors.surface)
                                    .cornerRadius(Theme.Radius.medium)

                                    HStack {
                                        TextField("Fat", text: $fatText)
                                            .keyboardType(.decimalPad)
                                        Text("g").foregroundColor(Theme.Colors.textSecondary)
                                    }
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .background(Theme.Colors.surface)
                                    .cornerRadius(Theme.Radius.medium)

                                    HStack {
                                        TextField("Serving size", text: $gramsText)
                                            .keyboardType(.decimalPad)
                                        Text("g").foregroundColor(Theme.Colors.textSecondary)
                                    }
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .background(Theme.Colors.surface)
                                    .cornerRadius(Theme.Radius.medium)
                                }

                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.error)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                    }
                }
            }
            .navigationTitle("Add Meal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveMeal() }
                        .disabled(isSaving || mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        Task {
            do {
                searchResults = try await OpenFoodFactsService.shared.search(query: searchText)
                isSearching = false
            } catch {
                isSearching = false
                searchResults = []
            }
        }
    }

    private func selectFood(_ product: OFFProduct) {
        mealName = product.name
        caloriesText = String(Int(product.caloriesPer100g ?? 0))
        proteinText = String(format: "%.1f", product.proteinPer100g ?? 0)
        carbsText = String(format: "%.1f", product.carbsPer100g ?? 0)
        fatText = String(format: "%.1f", product.fatPer100g ?? 0)
        gramsText = "100"
        searchResults = []
        searchText = ""
        showManualEntry = true
    }

    private func saveMeal() {
        if isSaving { return }
        let trimmedName = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Meal name is required."
            return
        }

        errorMessage = nil
        isSaving = true

        let calories = Int(caloriesText) ?? 0
        let protein = Double(proteinText) ?? 0
        let carbs = Double(carbsText) ?? 0
        let fat = Double(fatText) ?? 0
        let grams = Double(gramsText) ?? 100

        let itemRequest = FoodItemCreateRequestDTO(
            name: trimmedName,
            grams: grams,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            fiberG: nil,
            source: .manual,
            servingSize: grams,
            servingUnit: "g",
            servings: 1,
            barcode: nil,
            offProductId: nil,
            nutriScoreGrade: nil,
            confidence: nil,
            portionDescription: nil
        )
        let request = MealCreateRequestDTO(
            name: trimmedName,
            mealType: mealType,
            timestamp: date,
            notes: notes.isEmpty ? nil : notes,
            photoUrl: nil,
            items: [itemRequest],
            localId: nil
        )

        Task {
            do {
                let response = try await APIService.shared.createMeal(request: request)
                await MainActor.run {
                    upsertMeal(response, modelContext: modelContext)
                    try? modelContext.save()
                    isSaving = false
                    onSaved?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

}

struct BarcodeScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var manualCode = ""
    @State private var product: OFFProduct?
    @State private var isLookingUp = false
    @State private var gramsText = ""
    @State private var servings: Double = 1
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var hasCameraPermission = AVCaptureDevice.authorizationStatus(for: .video) != .denied
    private let servingOptions: [Double] = [0.25, 0.5, 1, 1.5, 2, 2.5, 3, 4, 5]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    if hasCameraPermission {
                        BarcodeScannerPreview { code in
                            handleScannedCode(code)
                        }
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.large)
                                .stroke(Theme.Colors.border, lineWidth: 1)
                        )
                    } else {
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.Colors.textTertiary)
                            Text("Camera access is needed to scan barcodes.")
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.lg)
                        .cardStyle()
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Enter barcode manually")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                        HStack {
                            TextField("0123456789012", text: $manualCode)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.plain)
                                .padding(Theme.Spacing.sm)
                                .background(Theme.Colors.surface)
                                .cornerRadius(Theme.Radius.medium)
                            Button("Lookup") {
                                handleScannedCode(manualCode)
                            }
                            .buttonStyle(.secondary)
                            .disabled(manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    if isLookingUp {
                        SwiftUI.ProgressView("Looking up product...")
                            .tint(Theme.Colors.accent)
                            .padding(.vertical, Theme.Spacing.sm)
                    }

            if let product {
                productCard(product)
            }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Scan Barcode")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            requestCameraPermissionIfNeeded()
        }
    }

    @ViewBuilder
    private func productCard(_ product: OFFProduct) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(product.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                if let grade = product.nutriscoreGrade {
                    NutriScoreBadge(grade: grade)
                }
            }

            if let brands = product.brands {
                Text(brands)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            let totalGrams = selectedAmountInGrams(for: product)
            let totals = nutritionTotals(product: product, grams: totalGrams)

            HStack(spacing: Theme.Spacing.md) {
                nutritionChip(label: "Calories", value: "\(totals.calories)")
                nutritionChip(label: "Protein", value: String(format: "%.0fg", totals.protein))
                nutritionChip(label: "Net Carbs", value: String(format: "%.0fg", totals.netCarbs))
                nutritionChip(label: "Fat", value: String(format: "%.0fg", totals.fat))
            }

            if product.caloriesPerServing != nil || product.servingQuantity != nil || product.servingSize != nil {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text("Serving Size")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                        Text(servingSizeDisplay(product: product))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    HStack {
                        Text("Servings")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                        Text(String(format: "%.2g", servings))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    Picker("Servings", selection: $servings) {
                        ForEach(servingOptions, id: \.self) { value in
                            Text(String(format: "%.2g", value)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }
            } else {
                HStack {
                    TextField("Grams", text: $gramsText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.surface)
                        .cornerRadius(Theme.Radius.medium)
                    Text("g")
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            Button("Add to Meals") {
                addProductToMeals(product)
            }
            .buttonStyle(.primary)
            .disabled(isSaving)
        }
        .padding(Theme.Spacing.md)
        .cardStyle(elevated: true)
        .onAppear {
            servings = 1
            if gramsText.isEmpty {
                gramsText = String(format: "%.0f", product.defaultServingG)
            }
        }
    }

    private func nutritionChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.caption2)
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(Theme.Colors.surfaceHighlight)
        .cornerRadius(Theme.Radius.small)
    }

    private func handleScannedCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        manualCode = trimmed
        lookupProduct(for: trimmed)
    }

    private func lookupProduct(for code: String) {
        errorMessage = nil
        product = nil
        isLookingUp = true

        Task {
            defer { isLookingUp = false }
            do {
                product = try await OpenFoodFactsService.shared.lookupBarcode(code)
                if product == nil {
                    errorMessage = "No product found for that barcode."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addProductToMeals(_ product: OFFProduct) {
        if isSaving { return }
        let grams = selectedAmountInGrams(for: product)
        guard grams > 0 else {
            errorMessage = "Enter a valid amount."
            return
        }

        let item = product.toFoodItem(grams: grams)
        let request = MealCreateRequestDTO(
            name: product.name,
            mealType: .other,
            timestamp: Date(),
            notes: nil,
            photoUrl: nil,
            items: [foodItemRequest(from: item)],
            localId: nil
        )

        errorMessage = nil
        isSaving = true
        Task {
            do {
                let response = try await APIService.shared.createMeal(request: request)
                await MainActor.run {
                    upsertMeal(response, modelContext: modelContext)
                    try? modelContext.save()
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func requestCameraPermissionIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    hasCameraPermission = granted
                }
            }
        } else {
            hasCameraPermission = status != .denied && status != .restricted
        }
    }

    private func selectedAmountInGrams(for product: OFFProduct) -> Double {
        if product.caloriesPerServing != nil || product.servingQuantity != nil {
            let base = product.servingQuantity ?? product.defaultServingG
            return base * servings
        }
        return Double(gramsText) ?? 0
    }

    private func nutritionTotals(product: OFFProduct, grams: Double) -> (calories: Int, protein: Double, netCarbs: Double, fat: Double) {
        let multiplier = grams / 100.0
        let caloriesPerServing = product.caloriesPerServing
        let proteinPerServing = product.proteinPerServing
        let fatPerServing = product.fatPerServing
        let netCarbsPerServing = product.netCarbsPerServing

        let caloriesPer100g = Double(product.caloriesPer100g ?? 0)
        let proteinPer100g = product.proteinPer100g ?? 0
        let fatPer100g = product.fatPer100g ?? 0
        let netCarbsPer100g = max(
            0,
            (product.carbsPer100g ?? 0) - (product.fiberPer100g ?? 0) - (product.sugarAlcoholPer100g ?? 0)
        )

        let calories = caloriesPerServing != nil
            ? Int(round((caloriesPerServing ?? 0) * servings))
            : Int(round(caloriesPer100g * multiplier))
        let protein = proteinPerServing != nil
            ? (proteinPerServing ?? 0) * servings
            : proteinPer100g * multiplier
        let fat = fatPerServing != nil
            ? (fatPerServing ?? 0) * servings
            : fatPer100g * multiplier
        let netCarbs = netCarbsPerServing != nil
            ? (netCarbsPerServing ?? 0) * servings
            : netCarbsPer100g * multiplier
        return (calories, protein, netCarbs, fat)
    }

    private func servingUnit(for product: OFFProduct) -> String? {
        guard let servingSize = product.servingSize?.lowercased() else { return nil }
        if servingSize.contains("ml") { return "ml" }
        if servingSize.contains("g") { return "g" }
        if servingSize.contains("oz") { return "oz" }
        return nil
    }

    private func servingSizeDisplay(product: OFFProduct) -> String {
        if let servingSize = product.servingSize, !servingSize.isEmpty {
            return servingSize
        }
        if let quantity = product.servingQuantity, let unit = servingUnit(for: product) {
            return String(format: "%.0f %@", quantity, unit)
        }
        return String(format: "%.0f g", product.defaultServingG)
    }

}

private struct NutriScoreBadge: View {
    let grade: String

    var body: some View {
        Text(grade.uppercased())
            .font(Theme.Typography.caption2)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 2)
            .background(badgeColor)
            .foregroundColor(.black)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch grade.lowercased() {
        case "a": return Color.green.opacity(0.8)
        case "b": return Color.green.opacity(0.6)
        case "c": return Color.yellow.opacity(0.8)
        case "d": return Color.orange.opacity(0.8)
        case "e": return Color.red.opacity(0.8)
        default: return Theme.Colors.surfaceHighlight
        }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraImagePicker

        init(_ parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct EditMealView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var mealName: String
    @State private var mealType: MealType
    @State private var itemGrams: [UUID: String]
    @State private var errorMessage: String?
    @State private var deletedItemIDs = Set<UUID>()
    @State private var isSaving = false

    let meal: Meal

    init(meal: Meal) {
        self.meal = meal
        _mealName = State(initialValue: meal.name)
        _mealType = State(initialValue: meal.mealType)
        _itemGrams = State(
            initialValue: Dictionary(uniqueKeysWithValues: meal.items.map { ($0.id, String(format: "%.0f", $0.grams)) })
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Meal name", text: $mealName)
                    Picker("Meal Type", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section("Items") {
                    if meal.items.isEmpty {
                        Text("No items")
                            .foregroundColor(Theme.Colors.textSecondary)
                    } else {
                        ForEach(visibleItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: Theme.Spacing.xs) {
                                        Text(item.name)
                                            .font(Theme.Typography.subheadline)
                                        if let grade = item.nutriScoreGrade, !grade.isEmpty {
                                            NutriScoreBadge(grade: grade)
                                        }
                                    }
                                    Text("\(item.calories) cal")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                TextField("g", text: Binding(
                                    get: { itemGrams[item.id] ?? "" },
                                    set: { itemGrams[item.id] = $0 }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                                Text("g")
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                        .onDelete(perform: deleteItems)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(Theme.Colors.error)
                }
            }
            .navigationTitle("Edit Meal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveChanges() }
                        .disabled(isSaving)
                }
            }
        }
    }

    private var visibleItems: [FoodItem] {
        meal.items.filter { !deletedItemIDs.contains($0.id) }
    }

    private func deleteItems(at offsets: IndexSet) {
        let items = visibleItems
        for index in offsets {
            let item = items[index]
            deletedItemIDs.insert(item.id)
            itemGrams[item.id] = nil
        }
    }

    private func saveChanges() {
        if isSaving { return }
        let trimmed = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Meal name is required."
            return
        }

        errorMessage = nil
        isSaving = true

        let updatedItems: [(FoodItem, FoodItemUpdateRequestDTO)] = visibleItems.compactMap { item in
            guard let gramsString = itemGrams[item.id],
                  let newGrams = Double(gramsString),
                  newGrams > 0 else { return nil }

            if item.grams == 0 || newGrams == item.grams {
                return nil
            }

            let factor = newGrams / item.grams
            let updatedCalories = Int(round(Double(item.calories) * factor))
            return (item, FoodItemUpdateRequestDTO(
                name: nil,
                grams: newGrams,
                calories: updatedCalories,
                proteinG: item.proteinG * factor,
                carbsG: item.carbsG * factor,
                fatG: item.fatG * factor,
                fiberG: item.fiberG.map { $0 * factor },
                sodiumMg: item.sodiumMg.map { $0 * factor },
                sugarG: item.sugarG.map { $0 * factor },
                saturatedFatG: item.saturatedFatG.map { $0 * factor },
                servingSize: item.servingSize,
                servingUnit: item.servingUnit,
                servings: item.servings,
                barcode: item.barcode,
                offProductId: item.offProductId,
                nutriScoreGrade: item.nutriScoreGrade,
                confidence: item.confidence,
                portionDescription: item.portionDescription
            ))
        }

        let hasMealUpdate = trimmed != meal.name || mealType != meal.mealType
        let mealUpdate = MealUpdateRequestDTO(
            name: trimmed != meal.name ? trimmed : nil,
            mealType: mealType != meal.mealType ? mealType : nil,
            timestamp: nil,
            notes: nil,
            photoUrl: nil
        )

        Task {
            do {
                var latestResponse: MealResponseDTO?

                for itemId in deletedItemIDs {
                    latestResponse = try await APIService.shared.deleteFoodItem(mealId: meal.id, itemId: itemId)
                }

                for (item, request) in updatedItems {
                    latestResponse = try await APIService.shared.updateFoodItem(
                        mealId: meal.id,
                        itemId: item.id,
                        request: request
                    )
                }

                if hasMealUpdate {
                    latestResponse = try await APIService.shared.updateMeal(id: meal.id, request: mealUpdate)
                }

                await MainActor.run {
                    if let response = latestResponse {
                        upsertMeal(response, modelContext: modelContext)
                        try? modelContext.save()
                    }
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct FoodPhotoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem?
    @State private var cameraImage: UIImage?
    @State private var showingCameraPicker = false
    @State private var pendingImageData: Data?
    @State private var imageData: Data?
    @State private var analysis: VisionAnalyzeResponse?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var mealType: MealType = .other
    @State private var showingPhotoConfirmation = false
    private var isCameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    Button {
                        showingCameraPicker = true
                    } label: {
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.Colors.accent)
                            Text("Take Photo")
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.lg)
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                    .disabled(!isCameraAvailable)

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.Colors.accent)
                            Text(imageData == nil ? "Choose from Library" : "Choose Different Photo")
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.lg)
                        .cardStyle()
                    }

                    if let imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.large)
                                    .stroke(Theme.Colors.border, lineWidth: 1)
                            )
                    }

                    if isAnalyzing {
                        SwiftUI.ProgressView("Analyzing photo...")
                            .tint(Theme.Colors.accent)
                            .padding(.vertical, Theme.Spacing.sm)
                    }

                    if let analysis {
                        analysisCard(analysis)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Photo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                loadPhotoForConfirmation(from: newItem)
            }
            .onChange(of: cameraImage) { _, newImage in
                guard let newImage else { return }
                loadPhotoForConfirmation(from: newImage)
            }
            .confirmationDialog(
                "Confirm Photo",
                isPresented: $showingPhotoConfirmation,
                presenting: pendingImageData
            ) { imageData in
                Button("Analyze Photo") {
                    self.imageData = imageData
                    analyzePhoto()
                }
                Button("Choose Different Photo", role: .cancel) {
                    pendingImageData = nil
                }
            } message: { _ in
                Text("Use this photo for food analysis?")
            }
            .sheet(isPresented: $showingCameraPicker) {
                CameraImagePicker(image: $cameraImage)
            }
        }
    }

    @ViewBuilder
    private func analysisCard(_ analysis: VisionAnalyzeResponse) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("AI Analysis")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(analysis.description)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.md) {
                nutritionChip(label: "Calories", value: "\(Int(round(analysis.totals.calories)))")
                nutritionChip(label: "Protein", value: String(format: "%.0fg", analysis.totals.proteinG))
                nutritionChip(label: "Carbs", value: String(format: "%.0fg", analysis.totals.carbsG))
                nutritionChip(label: "Fat", value: String(format: "%.0fg", analysis.totals.fatG))
            }

            Picker("Meal Type", selection: $mealType) {
                ForEach(MealType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }

            if !analysis.items.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Items")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                    ForEach(analysis.items) { item in
                        HStack {
                            Text(item.name)
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Spacer()
                            Text("\(Int(round(item.calories))) cal")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }
            }

            Button("Add to Meals") {
                addAnalysisToMeals(analysis)
            }
            .buttonStyle(.primary)
            .disabled(isSaving)
        }
        .padding(Theme.Spacing.md)
        .cardStyle(elevated: true)
    }

    private func nutritionChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.caption2)
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(Theme.Colors.surfaceHighlight)
        .cornerRadius(Theme.Radius.small)
    }

    private func loadPhotoForConfirmation(from item: PhotosPickerItem) {
        errorMessage = nil
        analysis = nil

        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        pendingImageData = data
                        showingPhotoConfirmation = true
                    }
                    return
                }
            } catch {
                // fall through to try other representations
            }

            if let data = await loadPhotoAssetData(from: item) {
                await MainActor.run {
                    pendingImageData = data
                    showingPhotoConfirmation = true
                }
                return
            }

            await MainActor.run {
                errorMessage = "Could not read that photo. If it is in iCloud, open it in Photos to download first."
            }
        }
    }

    private func loadPhotoForConfirmation(from image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            errorMessage = "Could not process the photo."
            return
        }
        pendingImageData = data
        showingPhotoConfirmation = true
    }

    private func analyzePhoto() {
        guard let data = imageData else { return }
        Task {
            await analyzeImageData(data)
        }
    }

    private func analyzeImageData(from image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            await MainActor.run {
                errorMessage = "Could not process the photo."
                isAnalyzing = false
            }
            return
        }
        await analyzeImageData(data)
    }

    private func analyzeImageData(_ data: Data) async {
        await MainActor.run {
            errorMessage = nil
            analysis = nil
            isAnalyzing = true
        }
        do {
            let analysisResult = try await APIService.shared.analyzeFood(imageBase64: data.base64EncodedString())
            await MainActor.run {
                imageData = data
                analysis = analysisResult
                isAnalyzing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = friendlyPhotoError(error)
                isAnalyzing = false
            }
        }
    }

    private func loadPhotoAssetData(from item: PhotosPickerItem) async -> Data? {
        guard let identifier = item.itemIdentifier else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func friendlyPhotoError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return "Could not read that photo. Try a different image."
        }
        return error.localizedDescription
    }

    private func addAnalysisToMeals(_ analysis: VisionAnalyzeResponse) {
        let mealName = analysis.description.isEmpty ? "Photo Meal" : analysis.description
        let items: [FoodItem] = analysis.items.isEmpty
            ? [
                FoodItem(
                    name: mealName,
                    source: .vision,
                    grams: 0,
                    calories: Int(round(analysis.totals.calories)),
                    proteinG: analysis.totals.proteinG,
                    carbsG: analysis.totals.carbsG,
                    fatG: analysis.totals.fatG,
                    confidence: analysis.confidence,
                    portionDescription: analysis.description
                )
            ]
            : analysis.items.map { $0.toFoodItem() }

        let request = MealCreateRequestDTO(
            name: mealName,
            mealType: mealType,
            timestamp: Date(),
            notes: nil,
            photoUrl: nil,
            items: items.map { foodItemRequest(from: $0) },
            localId: nil
        )

        errorMessage = nil
        isSaving = true
        Task {
            do {
                let response = try await APIService.shared.createMeal(request: request)
                await MainActor.run {
                    upsertMeal(response, modelContext: modelContext)
                    try? modelContext.save()
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

}

private func upsertMeal(_ response: MealResponseDTO, modelContext: ModelContext) {
    let responseId = response.id
    let existingDescriptor = FetchDescriptor<Meal>(
        predicate: #Predicate<Meal> { $0.id == responseId }
    )
    if let existing = try? modelContext.fetch(existingDescriptor).first {
        modelContext.delete(existing)
    }

    let meal = Meal(
        id: response.id,
        userId: response.userId,
        name: response.name,
        mealType: response.mealType,
        timestamp: response.timestamp,
        notes: response.notes
    )

    for item in response.items {
        let food = FoodItem(
            id: item.id,
            name: item.name,
            source: item.source,
            grams: item.grams,
            calories: item.calories,
            proteinG: item.proteinG,
            carbsG: item.carbsG,
            fatG: item.fatG,
            fiberG: item.fiberG,
            servingSize: item.servingSize,
            servingUnit: item.servingUnit,
            servings: item.servings,
            barcode: item.barcode,
            nutriScoreGrade: item.nutriScoreGrade,
            confidence: item.confidence,
            portionDescription: item.portionDescription
        )
        food.sodiumMg = item.sodiumMg
        food.sugarG = item.sugarG
        food.saturatedFatG = item.saturatedFatG
        food.createdAt = item.createdAt
        meal.items.append(food)
    }

    meal.totalCalories = response.totalCalories
    meal.totalProteinG = response.totalProteinG
    meal.totalCarbsG = response.totalCarbsG
    meal.totalFatG = response.totalFatG
    meal.totalFiberG = response.totalFiberG
    meal.isSynced = true
    meal.createdAt = response.createdAt
    meal.updatedAt = response.updatedAt

    modelContext.insert(meal)
}

private func foodItemRequest(from item: FoodItem) -> FoodItemCreateRequestDTO {
    FoodItemCreateRequestDTO(
        name: item.name,
        grams: item.grams,
        calories: item.calories,
        proteinG: item.proteinG,
        carbsG: item.carbsG,
        fatG: item.fatG,
        fiberG: item.fiberG,
        source: item.source,
        servingSize: item.servingSize,
        servingUnit: item.servingUnit,
        servings: item.servings,
        barcode: item.barcode,
        offProductId: item.offProductId,
        nutriScoreGrade: item.nutriScoreGrade,
        confidence: item.confidence,
        portionDescription: item.portionDescription
    )
}

// MARK: - Barcode Scanner Preview

private struct BarcodeScannerPreview: UIViewRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIView(context: Context) -> ScannerView {
        let view = ScannerView()
        context.coordinator.configureSession(for: view, onCodeScanned: onCodeScanned)
        return view
    }

    func updateUIView(_ uiView: ScannerView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private var onCodeScanned: ((String) -> Void)?
        private var hasScanned = false

        func configureSession(for view: ScannerView, onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
            session.beginConfiguration()

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .qr]

            session.commitConfiguration()

            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hasScanned,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = object.stringValue else {
                return
            }
            hasScanned = true
            onCodeScanned?(code)
            session.stopRunning()
        }
    }
}

private final class ScannerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

#Preview {
    FoodView()
        .environmentObject(AppState())
        .modelContainer(for: [Meal.self])
}
