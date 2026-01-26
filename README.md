# Logged

Logged is a dark minimalist workout + nutrition tracker with an AI assistant that can estimate macros and log meals/workouts via chat.

![Logged Logo](docs/logo-placeholder.png)

## Features

### Core Tracking
- **Nutrition Tracking**: Log meals with detailed macros (calories, protein, carbs, fat, fiber)
- **Workout Planning**: Create workout templates and log sessions
- **Body Weight**: Track weight trends over time
- **Water Intake**: Monitor daily hydration
- **Progress Charts**: Visualize trends with filterable date ranges

### AI Features
- **Logged Chat Assistant**: Natural language interface for logging
  - "I had 2 eggs and toast for breakfast"
  - "Log 500ml water"
  - "I did 30 minutes of running"
- **Meal Vision Analyzer**: Take a photo of your food for AI-estimated macros
- **Smart Macro Calculator**: Auto-calculates targets based on your goals and body metrics

### Integrations
- **Apple HealthKit**: Sync steps, active calories, and workouts
- **Open Food Facts**: Barcode scanning for instant nutrition lookup

## Architecture

```
ada/
├── ios/Ada/                  # iOS SwiftUI app
│   ├── App/                  # App entry point
│   ├── Models/               # SwiftData models
│   ├── ViewModels/           # MVVM view models
│   ├── Views/                # SwiftUI views
│   ├── Services/             # Business logic services
│   └── Utilities/            # Theme, constants, extensions
├── backend/                  # FastAPI backend
│   ├── app/
│   │   ├── models/           # SQLAlchemy models
│   │   ├── schemas/          # Pydantic schemas
│   │   ├── routes/           # API endpoints
│   │   ├── services/         # Business logic
│   │   └── utils/            # Utilities
│   ├── migrations/           # Alembic migrations
│   └── tests/                # pytest tests
├── shared/api/               # OpenAPI spec
└── docs/                     # Documentation
```

## Tech Stack

### iOS App
- **SwiftUI** - Modern declarative UI
- **SwiftData** - Local persistence
- **Combine** - Reactive programming
- **Charts** - Progress visualization
- **HealthKit** - Fitness data integration
- **AVFoundation** - Barcode scanning

### Backend
- **FastAPI** - Async Python web framework
- **Neon PostgreSQL** - Primary database (Postgres-compatible)
- **SQLAlchemy** - Async ORM
- **Anthropic Claude** - AI chat and vision (default)
- **OpenAI API** - Optional AI provider
- **JWT** - Authentication

## Getting Started

### Prerequisites
- Xcode 15+ (for iOS app)
- Python 3.11+
- PostgreSQL 15+ (only if not using Neon)
- Docker (optional)

### Backend Setup

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/logged.git
cd logged
```

2. **Create environment file**
```bash
cd backend
cp .env.example .env
# Edit .env with your configuration
```

3. **Start with Docker Compose** (recommended)
```bash
docker-compose up -d
```

For local Postgres instead of Neon:
```bash
docker-compose --profile local-db up -d
```

Or **manually**:
```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start PostgreSQL (if not using Neon)
# ... (ensure PostgreSQL is running)

# Run migrations
alembic upgrade head

# Start server
uvicorn app.main:app --reload
```

4. **Access API documentation**
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

### iOS App Setup

1. **Open Xcode project**
```bash
cd ios/Ada
open Ada.xcodeproj
```

2. **Configure signing**
- Select your development team in project settings

3. **Update API configuration**
- Edit `Constants.swift` to point to your backend URL

4. **Build and run**
- Select a simulator or device
- Press Cmd+R to build and run

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | Neon PostgreSQL connection string (include `?sslmode=require`) | `postgresql+asyncpg://user:pass@host/db?sslmode=require` |
| `AUTH_DATABASE_URL` | Optional separate auth DB (defaults to `DATABASE_URL`) | (optional) |
| `JWT_SECRET_KEY` | Secret key for JWT tokens | (required) |
| `AI_PROVIDER` | `anthropic` or `openai` | `anthropic` |
| `ANTHROPIC_API_KEY` | Anthropic API key for AI features | (required for Anthropic) |
| `CLAUDE_MODEL` | Model for chat | `claude-sonnet-4-20250514` |
| `CLAUDE_VISION_MODEL` | Model for vision | `claude-sonnet-4-20250514` |
| `CLAUDE_MAX_TOKENS` | Max tokens for AI responses | `4096` |
| `OPENAI_API_KEY` | OpenAI API key for AI features | (optional) |
| `OPENAI_MODEL` | Model for chat | `gpt-4-turbo-preview` |
| `OPENAI_VISION_MODEL` | Model for vision | `gpt-4-vision-preview` |
| `OPENAI_BASE_URL` | OpenAI-compatible base URL | (optional) |

If `AUTH_DATABASE_URL` is set to a different Neon database, the backend will mirror user profile records there for auth isolation. The primary app data still lives in `DATABASE_URL`.

## API Endpoints

### Authentication
- `POST /auth/magic-link` - Request magic link email
- `POST /auth/verify` - Verify magic link token
- `POST /auth/apple` - Sign in with Apple
- `POST /auth/refresh` - Refresh access token

### User
- `GET /user/profile` - Get user profile
- `PUT /user/profile` - Update profile
- `POST /user/targets/calculate` - Calculate macro targets

### Nutrition
- `GET /nutrition/meals` - List meals
- `POST /nutrition/meals` - Create meal
- `GET /nutrition/foods/search` - Search foods
- `GET /nutrition/foods/barcode/{code}` - Barcode lookup

### Workouts
- `GET /workouts/plans` - List workout plans
- `POST /workouts/plans` - Create plan
- `GET /workouts/logs` - List workout logs
- `POST /workouts/logs` - Log workout

### Tracking
- `GET /tracking/weight` - Get weight entries
- `POST /tracking/weight` - Log weight
- `GET /tracking/water` - Get water entries
- `POST /tracking/water` - Log water
- `GET /tracking/daily/{date}` - Get daily summary

### AI
- `POST /ai/chat` - Chat with Logged assistant
- `POST /ai/vision/analyze` - Analyze food photo

## Macro Calculator

Uses the **Mifflin-St Jeor** equation:

**BMR Calculation:**
- Male: BMR = (10 × weight_kg) + (6.25 × height_cm) - (5 × age) + 5
- Female: BMR = (10 × weight_kg) + (6.25 × height_cm) - (5 × age) - 161

**Activity Multipliers:**
| Level | Multiplier |
|-------|------------|
| Sedentary | 1.2 |
| Light | 1.375 |
| Moderate | 1.55 |
| Active | 1.725 |
| Very Active | 1.9 |

**Goal Adjustments:**
- Cut: TDEE - (rate × 1100 cal/kg/week)
- Maintain: TDEE
- Bulk: TDEE + (rate × 550 cal/kg/week)

## Testing

### Backend Tests
```bash
cd backend
pytest
pytest --cov=app  # With coverage
```

### iOS Tests
Run tests in Xcode with Cmd+U

## Design System

Logged uses a dark minimalist theme:

- **Background**: `#0A0A0A`
- **Surface**: `#141414`
- **Accent**: `#6366F1` (Indigo)
- **Protein**: `#EF4444` (Red)
- **Carbs**: `#F59E0B` (Amber)
- **Fat**: `#8B5CF6` (Purple)
- **Calories**: `#22C55E` (Green)

## Roadmap / TODOs

### MVP Complete
- [x] Backend API structure
- [x] iOS app architecture
- [x] User authentication (magic link)
- [x] Profile and macro calculator
- [x] Meal logging
- [x] Workout logging
- [x] Weight and water tracking
- [x] HealthKit integration
- [x] AI chat assistant
- [x] Vision meal analyzer
- [x] Progress charts

### Future Enhancements
- [ ] Apple Watch app
- [ ] Recipe builder
- [ ] Meal planning
- [ ] Social features
- [ ] Export data
- [ ] Workout video guides
- [ ] Custom exercise library
- [ ] Supplement tracking
- [ ] Sleep tracking integration
- [ ] Advanced analytics

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Open Food Facts](https://openfoodfacts.org/) for nutrition database
- [Anthropic](https://www.anthropic.com/) for Claude AI capabilities
- [OpenAI](https://openai.com/) for optional AI capabilities
- [FastAPI](https://fastapi.tiangolo.com/) for the excellent framework
- [SwiftUI](https://developer.apple.com/xcode/swiftui/) for modern iOS development
