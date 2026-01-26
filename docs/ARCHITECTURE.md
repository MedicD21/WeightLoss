# Ada Fitness Tracker - Architecture Document

## Overview

Ada is a dark minimalist workout + nutrition tracker with an AI assistant that can estimate macros and log meals/workouts via chat. The system follows a clean architecture with clear separation between UI, business logic, and data layers.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         iOS App (Ada)                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │   SwiftUI   │  │   Charts    │  │  AVFoundation│             │
│  │   Views     │  │   Graphs    │  │  (Barcode)   │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
│         │                │                │                     │
│  ┌──────┴────────────────┴────────────────┴──────┐             │
│  │              ViewModels (Combine)              │             │
│  └──────────────────────┬────────────────────────┘             │
│                         │                                       │
│  ┌──────────────────────┴────────────────────────┐             │
│  │                  Services Layer                │             │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────┐   │             │
│  │  │HealthKit │ │  OpenFF  │ │ AI Service   │   │             │
│  │  │ Service  │ │  Service │ │ (Vision+Chat)│   │             │
│  │  └──────────┘ └──────────┘ └──────────────┘   │             │
│  └──────────────────────┬────────────────────────┘             │
│                         │                                       │
│  ┌──────────────────────┴────────────────────────┐             │
│  │           Data Layer (SwiftData)              │             │
│  │  ┌──────────────────────────────────────┐     │             │
│  │  │    Local SQLite (Offline-First)       │     │             │
│  │  └──────────────────────────────────────┘     │             │
│  └───────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS/REST
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Backend Service                             │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  FastAPI Application                     │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐   │   │
│  │  │  Auth    │ │  Sync    │ │  AI      │ │  Food     │   │   │
│  │  │  Routes  │ │  Routes  │ │  Routes  │ │  Routes   │   │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └───────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│  ┌───────────────────────────┴─────────────────────────────┐   │
│  │                    Service Layer                         │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐   │   │
│  │  │  Auth    │ │  Macro   │ │  AI      │ │  OpenFF   │   │   │
│  │  │  Service │ │Calculator│ │  Service │ │  Client   │   │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └───────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│  ┌───────────────────────────┴─────────────────────────────┐   │
│  │              PostgreSQL Database                         │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  OpenAI API      │ │  Open Food Facts │ │  Apple HealthKit │
│  (Vision + Chat) │ │  API             │ │  (on-device)     │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

## Data Model

### Entity Relationship Diagram

```
┌─────────────────────┐
│    UserProfile      │
├─────────────────────┤
│ id: UUID            │
│ email: String       │
│ sex: Sex            │
│ age: Int            │
│ heightCm: Double    │
│ weightKg: Double    │
│ activityLevel: AL   │
│ goalType: GoalType  │
│ goalRate: Double    │
│ createdAt: Date     │
│ updatedAt: Date     │
└─────────┬───────────┘
          │ 1:1
          ▼
┌─────────────────────┐
│   MacroTargets      │
├─────────────────────┤
│ id: UUID            │
│ userId: UUID (FK)   │
│ calories: Int       │
│ proteinG: Double    │
│ carbsG: Double      │
│ fatG: Double        │
│ fiberG: Double?     │
│ calculatedAt: Date  │
└─────────────────────┘

┌─────────────────────┐       ┌─────────────────────┐
│       Meal          │ 1:N   │     FoodItem        │
├─────────────────────┤◄──────├─────────────────────┤
│ id: UUID            │       │ id: UUID            │
│ userId: UUID (FK)   │       │ mealId: UUID (FK)   │
│ name: String        │       │ name: String        │
│ timestamp: Date     │       │ source: FoodSource  │
│ totalCalories: Int  │       │ grams: Double       │
│ totalProtein: Double│       │ calories: Int       │
│ totalCarbs: Double  │       │ proteinG: Double    │
│ totalFat: Double    │       │ carbsG: Double      │
│ notes: String?      │       │ fatG: Double        │
└─────────────────────┘       │ fiberG: Double?     │
                              │ sodiumMg: Double?   │
                              │ sugarG: Double?     │
                              │ barcode: String?    │
                              │ servingSize: Double?│
                              └─────────────────────┘

┌─────────────────────┐       ┌─────────────────────┐
│   WorkoutPlan       │ 1:N   │  WorkoutExercise    │
├─────────────────────┤◄──────├─────────────────────┤
│ id: UUID            │       │ id: UUID            │
│ userId: UUID (FK)   │       │ planId: UUID (FK)   │
│ name: String        │       │ name: String        │
│ description: String?│       │ sets: Int           │
│ scheduledDays: [Int]│       │ reps: Int?          │
│ isActive: Bool      │       │ durationSec: Int?   │
│ createdAt: Date     │       │ restSec: Int        │
└─────────────────────┘       │ orderIndex: Int     │
                              └─────────────────────┘

┌─────────────────────┐       ┌─────────────────────┐
│   WorkoutLog        │ 1:N   │  WorkoutSetLog      │
├─────────────────────┤◄──────├─────────────────────┤
│ id: UUID            │       │ id: UUID            │
│ userId: UUID (FK)   │       │ logId: UUID (FK)    │
│ planId: UUID? (FK)  │       │ exerciseName: String│
│ type: WorkoutType   │       │ setNumber: Int      │
│ name: String        │       │ reps: Int?          │
│ startTime: Date     │       │ weightKg: Double?   │
│ endTime: Date?      │       │ durationSec: Int?   │
│ durationMin: Int    │       │ completed: Bool     │
│ caloriesBurned: Int?│       └─────────────────────┘
│ notes: String?      │
│ source: LogSource   │
│ healthKitId: String?│
└─────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  BodyWeightEntry    │  │    WaterEntry       │  │    StepsDaily       │
├─────────────────────┤  ├─────────────────────┤  ├─────────────────────┤
│ id: UUID            │  │ id: UUID            │  │ id: UUID            │
│ userId: UUID (FK)   │  │ userId: UUID (FK)   │  │ userId: UUID (FK)   │
│ weightKg: Double    │  │ amountMl: Int       │  │ date: Date          │
│ timestamp: Date     │  │ timestamp: Date     │  │ steps: Int          │
│ notes: String?      │  └─────────────────────┘  │ source: String      │
└─────────────────────┘                           │ syncedAt: Date      │
                                                  └─────────────────────┘

┌─────────────────────┐
│   ChatMessage       │
├─────────────────────┤
│ id: UUID            │
│ userId: UUID (FK)   │
│ role: MessageRole   │
│ content: String     │
│ toolCalls: JSON?    │
│ timestamp: Date     │
└─────────────────────┘
```

### Enums

```swift
enum Sex: String { case male, female }
enum ActivityLevel: String { case sedentary, light, moderate, active, veryActive }
enum GoalType: String { case cut, maintain, bulk }
enum FoodSource: String { case manual, openFoodFacts, barcode, vision, chat }
enum WorkoutType: String { case strength, cardio, hiit, flexibility, sports, other }
enum LogSource: String { case manual, healthKit, chat }
enum MessageRole: String { case user, assistant, system, tool }
```

## Macro Calculator Algorithm

### BMR Calculation (Mifflin-St Jeor)
```
Male:   BMR = (10 × weight_kg) + (6.25 × height_cm) - (5 × age) + 5
Female: BMR = (10 × weight_kg) + (6.25 × height_cm) - (5 × age) - 161
```

### Activity Multipliers (TDEE)
```
Sedentary:    BMR × 1.2
Light:        BMR × 1.375
Moderate:     BMR × 1.55
Active:       BMR × 1.725
Very Active:  BMR × 1.9
```

### Goal Adjustments
```
Cut (lose):   TDEE - (goal_rate_kg_per_week × 1100)  // ~7700 cal/kg deficit
Maintain:     TDEE
Bulk (gain):  TDEE + (goal_rate_kg_per_week × 550)   // slower surplus
```

### Macro Distribution (Default)
```
Protein: 0.8g per lb body weight (1.76g/kg), min 10% calories
Fat: 25% of calories
Carbs: Remaining calories
Fiber: 14g per 1000 calories
```

## AI Integration

### Vision Analyzer
- Input: Food photo (base64)
- Model: GPT-4 Vision or compatible
- Output: Structured JSON with food items and macro estimates
- Confidence scoring for user review

### Chat Assistant Tools
```json
{
  "tools": [
    {
      "name": "add_meal",
      "description": "Log a meal with food items",
      "parameters": { "name", "items[]", "timestamp?" }
    },
    {
      "name": "add_workout",
      "description": "Log a workout session",
      "parameters": { "type", "name", "durationMin", "exercises[]?" }
    },
    {
      "name": "add_water",
      "description": "Log water intake",
      "parameters": { "amountMl", "timestamp?" }
    },
    {
      "name": "add_weight",
      "description": "Log body weight",
      "parameters": { "weightKg", "timestamp?" }
    },
    {
      "name": "set_goal",
      "description": "Update user goals and recalculate macros",
      "parameters": { "goalType?", "goalRate?", "activityLevel?" }
    },
    {
      "name": "search_food",
      "description": "Search food database or scan barcode",
      "parameters": { "query?", "barcode?" }
    }
  ]
}
```

## Security & Privacy

### On-Device Data
- All user data stored locally first (SwiftData/SQLite)
- HealthKit data never leaves device unless user explicitly syncs
- Biometric/Keychain storage for sensitive tokens

### Cloud Data
- Optional sync to backend for backup/multi-device
- End-to-end encryption for synced data (future)
- Clear data residency indicators in UI

### API Security
- JWT tokens with short expiry
- Refresh token rotation
- Rate limiting on all endpoints
- Input validation and sanitization

## Offline-First Architecture

1. All writes go to local database first
2. Sync queue tracks pending changes
3. Background sync when online
4. Conflict resolution: last-write-wins with timestamps
5. Clear sync status indicators in UI

## Folder Structure

```
ada/
├── ios/
│   └── Ada/
│       ├── Ada.xcodeproj
│       ├── Ada/
│       │   ├── App/
│       │   │   ├── AdaApp.swift
│       │   │   └── AppDelegate.swift
│       │   ├── Models/
│       │   │   ├── UserProfile.swift
│       │   │   ├── MacroTargets.swift
│       │   │   ├── Meal.swift
│       │   │   ├── FoodItem.swift
│       │   │   ├── Workout.swift
│       │   │   ├── BodyWeight.swift
│       │   │   ├── Water.swift
│       │   │   └── ChatMessage.swift
│       │   ├── ViewModels/
│       │   │   ├── DashboardViewModel.swift
│       │   │   ├── FoodViewModel.swift
│       │   │   ├── WorkoutViewModel.swift
│       │   │   ├── ProgressViewModel.swift
│       │   │   ├── ProfileViewModel.swift
│       │   │   └── ChatViewModel.swift
│       │   ├── Views/
│       │   │   ├── Dashboard/
│       │   │   ├── Food/
│       │   │   ├── Workout/
│       │   │   ├── Progress/
│       │   │   ├── Profile/
│       │   │   ├── Chat/
│       │   │   └── Components/
│       │   ├── Services/
│       │   │   ├── HealthKitService.swift
│       │   │   ├── OpenFoodFactsService.swift
│       │   │   ├── AIService.swift
│       │   │   ├── MacroCalculator.swift
│       │   │   ├── SyncService.swift
│       │   │   └── AuthService.swift
│       │   ├── Utilities/
│       │   │   ├── Theme.swift
│       │   │   ├── Extensions.swift
│       │   │   └── Constants.swift
│       │   └── Resources/
│       │       └── Assets.xcassets
│       └── AdaTests/
├── backend/
│   ├── app/
│   │   ├── main.py
│   │   ├── config.py
│   │   ├── models/
│   │   ├── schemas/
│   │   ├── routes/
│   │   ├── services/
│   │   └── utils/
│   ├── migrations/
│   ├── tests/
│   ├── requirements.txt
│   └── Dockerfile
├── shared/
│   └── api/
│       └── openapi.yaml
├── docs/
│   └── ARCHITECTURE.md
└── README.md
```

## API Contract Summary

### Authentication
- `POST /auth/magic-link` - Request magic link
- `POST /auth/verify` - Verify magic link token
- `POST /auth/refresh` - Refresh access token
- `POST /auth/apple` - Sign in with Apple

### User
- `GET /user/profile` - Get user profile
- `PUT /user/profile` - Update profile
- `GET /user/targets` - Get macro targets
- `POST /user/targets/calculate` - Calculate new targets

### Nutrition
- `GET /meals` - List meals
- `POST /meals` - Create meal
- `GET /foods/search` - Search foods
- `GET /foods/barcode/{code}` - Lookup by barcode

### Workouts
- `GET /workouts/plans` - List workout plans
- `POST /workouts/plans` - Create plan
- `GET /workouts/logs` - List workout logs
- `POST /workouts/logs` - Log workout

### Tracking
- `GET /weight` - Get weight entries
- `POST /weight` - Log weight
- `GET /water` - Get water entries
- `POST /water` - Log water
- `GET /steps` - Get steps data

### AI
- `POST /ai/chat` - Send chat message
- `POST /ai/vision/analyze` - Analyze food photo

### Sync
- `POST /sync/push` - Push local changes
- `GET /sync/pull` - Pull remote changes
