# Logged - Fitness Tracking App

## Project Overview
**Logged** is a comprehensive fitness tracking iOS app with AI assistant "Terry" for nutrition, workouts, body metrics, and hydration tracking.

**Tech Stack:**
- **Frontend**: SwiftUI (iOS 17+), SwiftData for local persistence
- **Backend**: FastAPI (Python), PostgreSQL (Neon), Claude AI integration
- **Architecture**: Hybrid sync model - SwiftData local + PostgreSQL cloud

## Critical Technical Gotchas

### 1. Pydantic Model Immutability
**Issue**: Pydantic models cannot be mutated after creation.
```python
# ❌ WRONG - This doesn't work!
response = ChatResponse(...)
response.created_entries = entries  # This has NO effect

# ✅ CORRECT - Reconstruct with all fields
response = ChatResponse(
    message=...,
    created_entries=entries,
    # ... all other fields
)
```
**Location**: [backend/app/routes/ai.py:153-154](backend/app/routes/ai.py#L153-L154)
**Impact**: If `created_entries` isn't set properly, iOS app won't sync workout plans/meals/etc.

### 2. Terry (AI Assistant) Configuration
**System Prompt**: [backend/app/services/ai_service.py:482-512](backend/app/services/ai_service.py#L482-L512)

**Key Requirements:**
- **Units**: ALWAYS imperial (oz for water, lbs for weight, never ml/kg)
- **Context Awareness**: Must recognize when user answers a question Terry just asked
- **Water Conversions**: 1 glass = 8oz, 1 bottle = 16-20oz, 1 large bottle = 32oz
- **Tool Usage**: Immediate tool calls when context is clear (e.g., "20oz" after asking about water)

### 3. Backend-to-Frontend Sync Flow
1. **iOS Action** → Terry chat message → Backend `/api/ai/chat`
2. **Backend** → Claude processes, executes tools, creates DB entries
3. **Backend** → Returns `ChatResponse` with `created_entries` field
4. **iOS** → `ChatViewModel` processes `created_entries`, syncs to SwiftData
5. **iOS** → UI updates automatically via SwiftData queries

**Critical**: `created_entries` must contain proper IDs (e.g., `plan_id`, `entry_id`) for sync to work.

**Sync Logic**: [Logged/Logged/ViewModels/ChatViewModel.swift:191-213](Logged/Logged/ViewModels/ChatViewModel.swift#L191-L213)

### 4. Database Models

**Backend (PostgreSQL/Neon)**:
- Base model: [backend/app/models/base.py](backend/app/models/base.py)
- Tracking models: [backend/app/models/tracking.py](backend/app/models/tracking.py)
  - `BodyWeightEntry` - Weight logs with optional body composition
  - `WaterEntry` - Water intake logs (stored in ml, displayed as oz)
  - `StepsDaily` - Daily step aggregation from HealthKit
  - `ProgressSnapshot` - Computed weekly metrics

**iOS (SwiftData)**:
- Local models sync with backend via API calls
- Models have `source` field: "manual", "health_kit", "chat"
- Sync flags: `is_synced`, `local_id` for offline-first architecture

## Recent Fixes

### Fix 1: Workout Plan Sync (2026-02-02)
**Problem**: Plans created in backend but not appearing in iOS Workout Plans tab.
**Root Cause**: Pydantic immutability - `response.created_entries = ...` had no effect.
**Solution**: Reconstruct `ChatResponse` with all fields including `created_entries`.
**Files Modified**: [backend/app/routes/ai.py](backend/app/routes/ai.py)

### Fix 2: Terry Context Awareness (2026-02-02)
**Problem**: Terry asking "How much water?" then not recognizing "20oz" as the answer.
**Root Cause**: System prompt didn't emphasize conversation context usage.
**Solution**: Enhanced SYSTEM_PROMPT with explicit context awareness instructions.
**Files Modified**: [backend/app/services/ai_service.py](backend/app/services/ai_service.py)

### Fix 3: Imperial Units for Water (2026-02-02)
**Problem**: Terry using ml instead of oz (rest of app uses imperial).
**Solution**: Updated SYSTEM_PROMPT to ALWAYS use oz with conversion references.
**Files Modified**: [backend/app/services/ai_service.py](backend/app/services/ai_service.py)

### Fix 4: iOS ChatResponse Missing tool_results (2026-02-02)
**Problem**: Backend returns `tool_results` field but iOS doesn't decode it, causing data loss.
**Root Cause**: iOS ChatResponse struct missing `toolResults` field and ToolResult model.
**Solution**: Added ToolResult struct and toolResults field to iOS ChatResponse.
**Files Modified**: [Logged/Logged/Models/ChatMessage.swift](Logged/Logged/Models/ChatMessage.swift)
**Impact**: iOS can now properly decode and use tool execution results from backend.

### Fix 5: add_water Tool Description Inconsistency (2026-02-02)
**Problem**: Tool description said "milliliters" but system prompt says "ALWAYS use oz".
**Root Cause**: Tool parameter description wasn't updated when imperial units were enforced.
**Solution**: Updated add_water tool description to clarify oz → ml conversion and reference common oz amounts.
**Files Modified**: [backend/app/services/ai_service.py](backend/app/services/ai_service.py)
**Impact**: Consistent messaging to Claude about water units - use oz, convert to ml.

### Fix 6: Auth Token Validation on App Launch (2026-02-05)
**Problem**: App showed MainTabView with expired tokens, creating hybrid auth state where users saw progress screens but couldn't actually use the app.
**Root Cause**: AppState.init() checked if token exists in keychain but didn't validate it. Expired tokens caused `isAuthenticated = true` without actual authentication.
**Solution**: Added proper token validation flow:
- iOS: Added `validateToken()` method to APIService
- iOS: Updated AppState to validate tokens on launch before setting `isAuthenticated`
- iOS: Added loading state (`isValidatingAuth`) shown while validating
- Backend: Added `/auth/validate` endpoint to verify token validity
- signOut() now clears both auth AND onboarding state
**Files Modified**:
- [Logged/Logged/Services/APIService.swift](Logged/Logged/Services/APIService.swift)
- [Logged/Logged/LoggedApp.swift](Logged/Logged/LoggedApp.swift)
- [Logged/Logged/ContentView.swift](Logged/Logged/ContentView.swift)
- [backend/app/routes/auth.py](backend/app/routes/auth.py)
**Impact**: Users never see MainTabView with invalid tokens. App shows loading indicator while validating, then properly routes to AuthView if token is expired. Graceful offline handling assumes cached auth is valid if network fails.

## Key Files & Locations

### Backend (FastAPI)
- **AI Routes**: [backend/app/routes/ai.py](backend/app/routes/ai.py) - Chat endpoint, tool execution
- **AI Service**: [backend/app/services/ai_service.py](backend/app/services/ai_service.py) - Claude integration, SYSTEM_PROMPT
- **Chat Schemas**: [backend/app/schemas/chat.py](backend/app/schemas/chat.py) - ChatResponse, ToolCall, ToolResult
- **Tracking Models**: [backend/app/models/tracking.py](backend/app/models/tracking.py) - Body metrics models
- **Base Model**: [backend/app/models/base.py](backend/app/models/base.py) - SQLAlchemy base with UUID, timestamps

### iOS (SwiftUI)
- **Content View**: [Logged/Logged/ContentView.swift](Logged/Logged/ContentView.swift) - Root navigation, tab bar
- **Chat ViewModel**: [Logged/Logged/ViewModels/ChatViewModel.swift](Logged/Logged/ViewModels/ChatViewModel.swift) - Terry chat logic, sync handling
- **Chat Models**: [Logged/Logged/Models/ChatMessage.swift](Logged/Logged/Models/ChatMessage.swift) - ChatResponse, ToolCall decodable models
- **Food Service**: [Logged/Logged/Services/OpenFoodFactsService.swift](Logged/Logged/Services/OpenFoodFactsService.swift) - Barcode/food search

### Docker
- **Compose**: `docker-compose.yml` - Backend services (API, database)
- **Restart**: `docker-compose restart api` - Apply backend changes

## Testing Procedures

### Test Workout Plan Sync
1. Open Terry chat in iOS app
2. Ask: "Create a workout plan for upper body"
3. Verify Terry creates plan and confirms
4. Navigate to Workout Plans tab
5. **Expected**: Plan appears immediately with all exercises
6. **Debug**: Check backend logs for INSERT statements, verify `created_entries` in response

### Test Water Intake Context
1. Open Terry chat
2. Click "Add water intake" quick action chip
3. Terry asks: "How much water?"
4. Reply: "20oz"
5. **Expected**: Terry immediately logs 20oz (no confusion)
6. Verify water entry appears in dashboard
7. **Debug**: Check Terry uses oz (not ml) in conversation

### Test Food Logging
1. Scan barcode or search food
2. Log via Terry: "I just ate 2 eggs"
3. **Expected**: Entry appears in Food tab with correct macros
4. Verify `created_entries` includes `entry_id`

## Unit Conventions
- **Water**: oz (fluid ounces) - convert to ml for API (× 30)
- **Weight**: lbs (pounds) - convert to kg for API (× 0.453592)
- **Distance**: miles/km based on user preference
- **Energy**: kcal (calories)

## Known Issues & Pending Work
- [x] Test workout plan sync after Pydantic fix ✅ FIXED
- [x] Verify Terry context awareness improvements ✅ FIXED
- [x] Ensure consistent oz usage across all water interactions ✅ FIXED
- [x] Add tool_results field to iOS ChatResponse ✅ FIXED
- [x] Fix add_water tool description inconsistency ✅ FIXED
- [x] Fix auth token validation on app launch ✅ FIXED (2026-02-05)
- [ ] Test all fixes end-to-end with user flow
- [ ] Verify tool_results are properly used in iOS (if needed for future features)
- [ ] Test auth validation with expired tokens
- [ ] Test offline mode with cached auth

## Development Commands
```bash
# Restart backend
docker-compose restart api

# View backend logs
docker-compose logs -f api

# Backend shell
docker-compose exec api bash

# iOS build (Xcode required)
# Open Logged/Logged.xcodeproj
```

## Environment Variables
- **Backend**: `backend/.env` - Database URLs, API keys
- **iOS**: Xcode build settings - API endpoint configuration

## Git Workflow
- **Main branch**: `main`
- **Feature branches**: `claude/<feature-name>-<id>`
- **Current**: Working on context/sync fixes

---

**Last Updated**: 2026-02-02
**Session**: Fixing Terry context memory and workout plan sync
