# MediFlow: Advanced AI-Driven Healthcare Logistics & Supply Chain Optimization

[![Status](https://img.shields.io/badge/Status-Production--Ready-success?style=for-the-badge)](https://github.com/pavsoss/MediFlow)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Backend-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
[![Gemini AI](https://img.shields.io/badge/Gemini-1.5--Flash-4285F4?style=for-the-badge&logo=google-gemini&logoColor=white)](https://ai.google.dev)

MediFlow is a high-performance, enterprise-grade medical logistics platform engineered to solve the "Last Mile" medical supply crisis. It utilizes Large Language Models (LLMs) for predictive demand forecasting and advanced heuristic algorithms for system-wide stock redistribution and route optimization.

---

## 🏛️ System Architecture

MediFlow follows a **Clean Architecture** pattern with a strict separation between the Domain Layer (Models), Data Layer (Services), and Presentation Layer (UI).

---

## 🚀 Comprehensive Feature Set

### 🏥 Facility Management Suite
Designed for local clinic and hospital managers to maintain hyper-local supply chain integrity.

*   **Real-time Inventory Command Center**: A high-density dashboard providing instant visibility into stock levels, burn rates, and replenishment needs.
*   **Daily Usage Logging Engine**: A transactional logging system that atomically updates inventory levels while simultaneously feeding data to the AI forecasting model.
*   **AI-Powered Demand Forecasting**: 
    *   Integrates **Gemini-1.5-Flash** to predict medicine usage for the next 30 days.
    *   Factors in historical logs, seasonal spikes (e.g., ORS for summer), and demographic data.
    *   Provides "AI Reasoning" to explain the logic behind suggested stock levels.
*   **Smart Alerts & Critical Tracking**: Automated detection of "Critical Stockouts" and "Near-Expiry" batches, ensuring managers never miss a replenishment window.
*   **Intelligent Request Management**: 
    *   Automatically drafts **Restock Requests** when inventory is low.
    *   Identifies local surpluses and drafts **Redistribution Offers** to help other facilities in the network.
*   **Integrated AI Assistant (Chat)**: A natural language interface that allows managers to query their inventory status, log usage via voice/text, and get instant logistics advice.

### 🏢 Central Admin Command Center
A bird's-eye view for regional administrators to optimize the entire healthcare network.

*   **Global Inventory Oversight**: Aggregated metrics across all facilities in the network, filtering by region or facility type (Rural vs. Urban).
*   **Centralized Approvals Pipeline**: A streamlined workflow for reviewing, editing, and approving incoming requests from dozens of facilities.
*   **Supply Status Tracking**: A comprehensive ledger tracking the end-to-end lifecycle of every request—from initial draft to final fulfillment.
*   **Advanced Route Optimization**:
    *   **Redistribution Logic**: A heuristic engine that matches surpluses to shortages to minimize system-wide wastage.
    *   **Road-Accurate Routing**: Integrated with **OSRM/ORS** to map out real-world delivery paths between donor and recipient sites.
    *   **Interactive Logistics Map**: Visual representation of the supply chain with color-coded markers (Donors vs. Recipients) and dynamic polyline overlays.
*   **Global Status Optimization**: A one-click feature to instantly recalculate the most efficient redistribution paths for the entire network based on live stock data.

---

## 🛠️ Technical Deep Dive

### 1. AI Forecasting Logic (`AIProvider`)
The forecasting engine pushes anonymized usage logs and demographic context to Gemini. The model returns a structured JSON forecast containing:
- **Predicted Daily Usage**: Granular day-by-day estimates.
- **Confidence Scoring**: Reliability of the prediction based on data density.
- **Seasonal Factor Detection**: Explaining why a spike is expected (e.g., "Post-monsoon waterborne disease risk").

### 2. Redistribution Algorithm (`OptimizationService`)
A weighted heuristic algorithm calculates the **Optimal Transfer Score (OTS)**:
$$OTS = (w_d \cdot Proximity) + (w_p \cdot RuralPriority) + (w_q \cdot QuantityMatch)$$
- **Proximity**: Inversed distance scoring using the Haversine formula.
- **Rural Priority**: Fixed-weight bonus for facilities classified as 'rural' to ensure technological equity.
- **Quantity Match**: Priority given to donors who can fulfill 100% of a recipient's deficit in a single trip.

### 3. Geospatial Routing Logic (`RoutingService`)
- **Engine**: Dynamic switching between OpenRouteService (primary) and OSRM (fallback).
- **Polyline Handling**: Decodes GeoJSON geometry coordinates into `LatLng` lists for high-fidelity map rendering.

---

## 📊 Data Schema (Firestore)

### `facilities` {Collection}
Stores metadata for clinics/hospitals.
- `id`: Unique Facility ID (derived from Auth)
- `type`: `rural` | `urban`
- `latitude` / `longitude`: Geo-coordinates for logistics

### `inventory` {Collection} -> `medicines` {Sub-collection}
Live stock tracking with atomic increments.
- `remainingQuantity`: Current count
- `initialQuantity`: Baseline for burn-rate calculations
- `expiryDate`: ISO 8601 timestamp

### `requests` {Collection}
The global ledger for movement of supplies.
- `type`: `shortage` | `surplus` | `regularIndent`
- `status`: `pending` | `approved` | `fulfilled`

---

## 🛡️ Security & Performance
- **Atomic Transactions**: All inventory updates use `runTransaction` to prevent race conditions.
- **Offline Persistence**: Local cache enabled for logging data in low-connectivity rural areas.
- **RBAC**: UI and API access gated via Riverpod-managed auth states.

---

## ⚙️ Getting Started

1. **Clone & Install**: `git clone` and `flutter pub get`.
2. **Environment**: Setup `.env` with `GEMINI_API_KEY` and `ORS_API_KEY`.
3. **Run**: `flutter run -d chrome`.

---

## 🤝 Acknowledgments
Built for the **Google Gemini AI Hackathon**, focusing on sustainable healthcare logistics and technological equity.

**Core Developers**: [Aarush Yadav](https://github.com/aarushyadav), [Paavni](https://github.com/paavni)

---
© 2026 MediFlow Team. *Engineering a smarter, healthier supply chain.*
