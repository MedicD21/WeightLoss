import SwiftUI
import SwiftData

/// View for searching food database or entering manually
struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [OFFProduct] = []
    @State private var selectedFood: OFFProduct?
    @State private var entryMode: FoodEntryMode = .search

    // Manual entry state
    @State private var manualFoodName = ""
    @State private var manualCalories = ""
    @State private var manualProtein = ""
    @State private var manualCarbs = ""
    @State private var manualFat = ""
    @State private var manualGrams = ""

    let onFoodSelected: (FoodItem) -> Void

    enum FoodEntryMode {
        case search
        case manual
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                // Mode toggle
                Picker("Entry Mode", selection: $entryMode) {
                    Text("Search").tag(FoodEntryMode.search)
                    Text("Manual").tag(FoodEntryMode.manual)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.md)

                if entryMode == .search {
                    searchModeContent
                } else {
                    manualModeContent
                }

                Spacer()
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var searchModeContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            SearchBar(text: $searchText, onSearch: performSearch)

            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Theme.Spacing.lg)
            } else if searchResults.isEmpty && !searchText.isEmpty {
                Text("No foods found")
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Theme.Spacing.lg)
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(searchResults, id: \.code) { product in
                            FoodSearchResultRow(product: product) {
                                selectedFood = product
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.md)
    }

    private var manualModeContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Search OFF first
            SearchBar(text: $searchText, onSearch: performSearch)

            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Theme.Spacing.lg)
            } else if !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Open Food Facts Results")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.md)

                    ScrollView {
                        VStack(spacing: Theme.Spacing.sm) {
                            ForEach(searchResults, id: \.code) { product in
                                FoodSearchResultRow(product: product) {
                                    selectedFood = product
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                    }
                    .frame(maxHeight: 300)
                }
            }

            Divider()
                .padding(.vertical, Theme.Spacing.sm)

            // Manual entry form
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Or Create Your Own")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)

                Form {
                    Section("Food Information") {
                        TextField("Food name", text: $manualFoodName)

                        HStack {
                            TextField("Calories", text: $manualCalories)
                                .keyboardType(.numberPad)
                            Text("cal").foregroundColor(Theme.Colors.textSecondary)
                        }

                        HStack {
                            TextField("Protein", text: $manualProtein)
                                .keyboardType(.decimalPad)
                            Text("g").foregroundColor(Theme.Colors.textSecondary)
                        }

                        HStack {
                            TextField("Carbs", text: $manualCarbs)
                                .keyboardType(.decimalPad)
                            Text("g").foregroundColor(Theme.Colors.textSecondary)
                        }

                        HStack {
                            TextField("Fat", text: $manualFat)
                                .keyboardType(.decimalPad)
                            Text("g").foregroundColor(Theme.Colors.textSecondary)
                        }

                        HStack {
                            TextField("Serving size", text: $manualGrams)
                                .keyboardType(.decimalPad)
                            Text("g").foregroundColor(Theme.Colors.textSecondary)
                        }
                    }

                    Button("Add Food") {
                        saveManualFood()
                    }
                    .buttonStyle(.primary)
                    .disabled(!isValidManualEntry)
                }
            }

            Spacer()
        }
        .padding(.vertical, Theme.Spacing.md)
    }

    private var isValidManualEntry: Bool {
        !manualFoodName.isEmpty && !manualCalories.isEmpty
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

    private func saveManualFood() {
        let food = FoodItem(
            id: UUID(),
            name: manualFoodName,
            source: .manual,
            grams: Double(manualGrams) ?? 100,
            calories: Int(manualCalories) ?? 0,
            proteinG: Double(manualProtein) ?? 0,
            carbsG: Double(manualCarbs) ?? 0,
            fatG: Double(manualFat) ?? 0
        )
        onFoodSelected(food)
        dismiss()
    }
}

/// Search bar component
private struct SearchBar: View {
    @Binding var text: String
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.Colors.textSecondary)

            TextField("Search foods...", text: $text)
                .textInputAutocapitalization(.none)
                .disableAutocorrection(true)
                .onSubmit(onSearch)

            if !text.isEmpty {
                Button(action: { text = "" }) {
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
    }
}

/// Food search result row
private struct FoodSearchResultRow: View {
    let product: OFFProduct
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(product.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)

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
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.Radius.medium)
        }
    }
}

#Preview {
    FoodSearchView { food in
        print("Selected: \(food.name)")
    }
}
