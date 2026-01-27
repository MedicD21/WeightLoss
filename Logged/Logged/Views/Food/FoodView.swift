import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI
import UIKit

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
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]
    @Environment(\.dismiss) private var dismiss

    @State private var manualCode = ""
    @State private var product: OFFProduct?
    @State private var isLookingUp = false
    @State private var gramsText = ""
    @State private var errorMessage: String?
    @State private var hasCameraPermission = AVCaptureDevice.authorizationStatus(for: .video) != .denied

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
            Text(product.name)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            if let brands = product.brands {
                Text(brands)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            HStack(spacing: Theme.Spacing.md) {
                nutritionChip(label: "Calories/100g", value: "\(product.caloriesPer100g ?? 0)")
                nutritionChip(label: "Protein", value: String(format: "%.0fg", product.proteinPer100g ?? 0))
                nutritionChip(label: "Carbs", value: String(format: "%.0fg", product.carbsPer100g ?? 0))
                nutritionChip(label: "Fat", value: String(format: "%.0fg", product.fatPer100g ?? 0))
            }

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

            Button("Add to Meals") {
                addProductToMeals(product)
            }
            .buttonStyle(.primary)
        }
        .padding(Theme.Spacing.md)
        .cardStyle(elevated: true)
        .onAppear {
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
        guard let grams = Double(gramsText), grams > 0 else {
            errorMessage = "Enter a valid gram amount."
            return
        }

        let profile = getOrCreateProfile()
        let meal = Meal(
            userId: profile.id,
            name: product.name,
            mealType: .other,
            timestamp: Date()
        )

        let item = product.toFoodItem(grams: grams)
        item.meal = meal
        meal.addItem(item)

        modelContext.insert(meal)
        modelContext.insert(item)
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
}

struct FoodPhotoView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var analysis: VisionAnalyzeResponse?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var mealType: MealType = .other

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.Colors.accent)
                            Text(imageData == nil ? "Choose Photo" : "Choose Different Photo")
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
                loadPhoto(from: newItem)
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
                nutritionChip(label: "Calories", value: "\(analysis.totals.calories)")
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
                            Text("\(item.calories) cal")
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

    private func loadPhoto(from item: PhotosPickerItem) {
        errorMessage = nil
        analysis = nil
        isAnalyzing = true

        Task {
            defer { isAnalyzing = false }
            do {
                imageData = try await item.loadTransferable(type: Data.self)
                guard let imageData else {
                    errorMessage = "Could not load the selected photo."
                    return
                }
                analysis = try await APIService.shared.analyzeFood(imageBase64: imageData.base64EncodedString())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addAnalysisToMeals(_ analysis: VisionAnalyzeResponse) {
        let profile = getOrCreateProfile()
        let mealName = analysis.description.isEmpty ? "Photo Meal" : analysis.description

        let meal = Meal(
            userId: profile.id,
            name: mealName,
            mealType: mealType,
            timestamp: Date()
        )

        for visionItem in analysis.items {
            let item = visionItem.toFoodItem()
            item.meal = meal
            meal.addItem(item)
            modelContext.insert(item)
        }

        if analysis.items.isEmpty {
            let fallback = FoodItem(
                name: mealName,
                source: .vision,
                grams: 0,
                calories: analysis.totals.calories,
                proteinG: analysis.totals.proteinG,
                carbsG: analysis.totals.carbsG,
                fatG: analysis.totals.fatG,
                confidence: analysis.confidence,
                portionDescription: analysis.description
            )
            fallback.meal = meal
            meal.addItem(fallback)
            modelContext.insert(fallback)
        }

        modelContext.insert(meal)
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
