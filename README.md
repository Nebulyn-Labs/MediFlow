# MediFlow: Advanced AI-Driven Healthcare Logistics & Supply Chain Optimization

[![Status](https://img.shields.io/badge/Status-Production--Ready-success?style=for-the-badge)](https://github.com/pavsoss/MediFlow)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Backend-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
[![Gemini AI](https://img.shields.io/badge/Gemini-1.5--Flash-4285F4?style=for-the-badge&logo=google-gemini&logoColor=white)](https://ai.google.dev)

MediFlow is a high-performance, enterprise-grade medical logistics platform engineered to solve the "Last Mile" medical supply crisis. It utilizes Large Language Models (LLMs) for predictive demand forecasting and advanced heuristic algorithms for system-wide stock redistribution and route optimization.

---

## 🏛️ System Architecture

MediFlow follows a **Clean Architecture** pattern with a strict separation between the Domain Layer (Models), Data Layer (Services), and Presentation Layer (UI).

### Component Interaction Flow
1. **Data Ingestion**: Facility managers log daily usage via the **Logging Engine**.
2. **Predictive Analysis**: The **AI Service** fetches historical logs and pushes context to **Gemini-1.5-Flash** to predict future stockouts.
3. **Redistribution**: The **Optimization Engine** cross-references system-wide shortages with surpluses using a multi-factor scoring heuristic.
4. **Execution**: The **Routing Service** converts approved transfers into road-accurate delivery paths via **OSRM/ORS**.

---

## 🛠️ Technical Deep Dive

### 1. AI Forecasting Engine (`AIProvider`)
The forecasting logic leverages Gemini's long-context window to analyze:
- **Burn Rates**: Rolling averages of medicine consumption.
- **Seasonality**: Detection of spikes (e.g., ORS demand during heatwaves).
- **Contextual Reasoning**: AI doesn't just provide numbers; it provides the *why* (e.g., "Predicting 20% increase due to pediatric demographic concentration").

### 2. Redistribution Algorithm (`OptimizationService`)
A weighted heuristic algorithm calculates the **Optimal Transfer Score (OTS)** for every shortage:
$$OTS = (w_d \cdot Proximity) + (w_p \cdot RuralPriority) + (w_q \cdot QuantityMatch)$$
- **Proximity**: Inversed distance scoring using the Haversine formula.
- **Rural Priority**: Fixed-weight bonus for facilities classified as 'rural' to ensure technological equity.
- **Quantity Match**: Priority given to donors who can fulfill 100% of a recipient's deficit in a single trip.

### 3. Geospatial Routing Logic (`RoutingService`)
- **Engine**: Dynamic switching between OpenRouteService (primary) and OSRM (fallback).
- **Polyline Handling**: Decodes GeoJSON geometry coordinates into `LatLng` lists for high-fidelity map rendering.
- **Optimization**: Supports dynamic route recalculation if supply priorities change in real-time.

---

## 📊 Data Schema (Firestore)

### `facilities` {Collection}
Stores metadata for clinics/hospitals.
- `id`: Unique Facility ID (derived from Auth)
- `type`: `rural` | `urban`
- `region`: Geographical zone for cluster analysis
- `latitude` / `longitude`: Geo-coordinates for logistics

### `inventory` {Collection} -> `medicines` {Sub-collection}
Live stock tracking with atomic increments.
- `medicineName`: Primary key
- `remainingQuantity`: Current count
- `initialQuantity`: Baseline for burn-rate calculations
- `expiryDate`: ISO 8601 timestamp

### `requests` {Collection}
The global ledger for movement of supplies.
- `type`: `restock` | `redistribution`
- `status`: `pending` | `approved` | `fulfilled`
- `quantity`: Amount requested/offered

---

## 🛡️ Security & Performance

- **Atomic Transactions**: All inventory updates use `FirebaseFirestore.runTransaction` to prevent race conditions during simultaneous logins.
- **RBAC (Role Based Access Control)**: UI and API access are strictly gated via Riverpod-managed auth states.
- **Offline Persistence**: Firestore's local cache is enabled, allowing clinic managers to log data in low-connectivity areas, with automatic sync on reconnection.

---

## 🚀 Deployment & Environment

### Environment Variables (.env)
```env
GEMINI_API_KEY=AIzaSy... # Google AI Studio
ORS_API_KEY=5b3ce...    # OpenRouteService
FIREBASE_PROJECT_ID=mediflow-prod
```

### Build Optimization
For web deployment, MediFlow uses the HTML renderer for better consistency with mapping overlays:
```bash
flutter build web --web-renderer html --release
```

---

## 🧪 Testing Suite
- **Unit Tests**: Logic verification for OTS scoring and polyline decoding.
- **Widget Tests**: Validation of the reactive sidebar and navigation flows.
- **Integration Tests**: End-to-end simulation of the "Request -> Approve -> Route" workflow.

---

## 🤝 Contribution & License
This project was developed for the **Google Gemini AI Hackathon**. 
Licensed under the [MIT License](LICENSE).

**Core Developers**: [Aarush Yadav](https://github.com/aarushyadav), [Paavni](https://github.com/paavni)

---
© 2026 MediFlow Team. *Engineering a smarter, healthier supply chain.*
