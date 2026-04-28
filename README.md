<p align="center">
  <img src="https://img.shields.io/badge/Google%20Solution%20Challenge-2026-4285F4?style=for-the-badge&logo=google&logoColor=white" alt="Google Solution Challenge 2026">
</p>

# 🧊 MediTrack AI
**Open Intelligent Cold-Chain Supply Chain Platform for Pharmaceutical Logistics**

<p align="center">
  <img src="https://img.shields.io/badge/SDG%203-Good%20Health%20%26%20Well--being-4CAF50?style=flat-square" alt="SDG 3">
  <img src="https://img.shields.io/badge/SDG%209-Industry%20%26%20Infrastructure-FF9800?style=flat-square" alt="SDG 9">
  <img src="https://img.shields.io/badge/SDG%2017-Partnerships%20for%20Goals-1976D2?style=flat-square" alt="SDG 17">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Firebase-039BE5?style=for-the-badge&logo=Firebase&logoColor=white" alt="Firebase">
  <img src="https://img.shields.io/badge/Gemini%20AI-8E75B2?style=for-the-badge&logo=google-gemini&logoColor=white" alt="Gemini AI">
  <img src="https://img.shields.io/badge/Google%20Maps-4285F4?style=for-the-badge&logo=google-maps&logoColor=white" alt="Google Maps">
  <img src="https://img.shields.io/badge/OpenRouteService-3E3E3E?style=for-the-badge&logo=openstreetmap&logoColor=white" alt="ORS">
</p>

<p align="center">
  <a href="#-project-overview">Problem</a> •
  <a href="#-the-problem--the-solution">Solution</a> •
  <a href="#-technical-architecture">Architecture</a> •
  <a href="#-the-team">Team</a>
</p>

---

## 📖 Table of Contents
- [Project Overview](#-project-overview)
- [The Problem & Solution](#-the-problem--the-solution)
- [Core Feature Set](#-core-feature-set)
  - [Hospital/Facility Module](#hospitalfacility-module)
  - [Central Administration Module](#central-administration-module)
- [Technical Architecture](#technical-architecture)
  - [The AI Engine (Gemini 1.5 Flash)](#1-the-ai-engine-gemini-15-flash)
  - [The Optimization Heuristic (OTS)](#2-the-optimization-heuristic-ots)
  - [Geospatial Routing System](#3-geospatial-routing-system)
- [Project Structure](#project-structure)
- [Data & Schema](#data--schema)
- [Development & Setup](#development--setup)
- [Roadmap](#roadmap)

---

## 🌟 Project Overview
**MediTrack AI** (formerly MediFlow) is an enterprise-grade medical logistics platform engineered to solve the "Last Mile" medical supply crisis. By combining **Generative AI** for demand forecasting with **Heuristic Optimization** for redistribution, MediTrack AI transforms a fragmented, reactive supply chain into a proactive, life-saving ecosystem, specifically targeting cold-chain pharmaceutical integrity.

## ⚠️ The Problem | The Solution
**The Crisis:** Rural clinics often face 30% higher stockout rates for essential antibiotics, while urban hospitals simultaneously dispose of expired stock due to over-purchasing. This inequality is compounded by the lack of intelligent monitoring for cold-chain medicines (vaccines, insulin).

**The MediTrack Solution:** We don't just track inventory; we **predict** shortages before they happen and **automate** the movement of medicine from surplus hospitals to deficit clinics using road-accurate route optimization, ensuring that every life-saving resource is allocated where it’s needed most.

---

## 🚀 Core Feature Set

### Hospital/Facility Module
*   **Smart Logging Engine**: Atomically track daily usage while the system computes burn rates in real-time.
*   **AI Forecasting (30-Day)**: Powered by **Gemini-1.5-Flash**, predicting seasonal spikes based on historical usage trends (e.g., ORS demand for summer) with a transparency-first "AI Reasoning" component.
*   **Automated Request Drafting**: Intelligent auto-population of restock indents and redistribution offers based on AI predictions.
*   **AI Chat Assistant**: A 24/7 logistics expert that facility managers can query for stock status, expiry alerts, or burn-rate insights.

### Central Administration Module
*   **Global Command Center**: Real-time regional oversight with deep-dive analytics into every facility's stock health.
*   **Multi-Step Approval Pipeline**: A secure hub for regional admins to review and prioritize redistribution plans.
*   **Interactive Logistics Map**: 
    *   **Donors vs. Recipients**: High-visibility markers distinguishing surplus sites from deficit clinics.
    *   **Road-Accurate Routing**: Integrated OSRM/ORS paths that calculate real-world travel time and distance.
*   **Global Optimization**: A "Global Redistribution Plan" that matches thousands of shortage items to local surpluses in seconds.

---

## 🏛️ Technical Architecture

MediTrack AI is built on **Clean Architecture** principles, ensuring that business logic is decoupled from the UI and external services.

### 1. The AI Engine (Gemini 1.5 Flash)
We leverage Gemini's large context window to process months of anonymized usage logs. The model acts as a **Predictive Reasoning Layer**, identifying non-obvious patterns like demographic-based medicine consumption surges.

### 2. The Optimization Heuristic (OTS)
Our proprietary **Optimal Transfer Score** ensures that redistribution is both efficient and equitable:
$$OTS = (w_{dist} \cdot Proximity) + (w_{prior} \cdot RuralPriority) + (w_{qty} \cdot QtyMatch)$$
*   **Proximity**: Minimizes logistics cost and time.
*   **Rural Priority**: A weight multiplier ensuring that remote facilities are never "starved" by the algorithm.

### 3. Geospatial Routing System
Integrated with **flutter_map** and **OSRM/OpenRouteService**, our routing engine decodes complex polylines to provide precise, road-accurate delivery paths, factoring in real-world geography.

---

## 📁 Project Structure

```bash
lib/
├── constants/
│   └── colors.dart             # Project-wide design tokens & premium palette
│
├── models/                     # Immutable Data Domain
│   ├── daily_usage_log.dart    # Atomic snapshots of medicine consumption
│   ├── facility.dart           # Metadata & Geospatial profiles for nodes
│   ├── inventory_item.dart     # Stock tracking & expiry metadata
│   ├── request.dart            # Ledger for redistribution & restock flows
│   └── usage_log.dart          # Helper models for analytics visualization
│
├── services/                   # Business Logic & Intelligence Layer
│   ├── ai_service.dart         # Gemini-1.5-Flash forecasting & reasoning
│   ├── chat_service.dart       # NLP pipeline for the AI Assistant
│   ├── firebase_service.dart   # Firestore infrastructure & transactions
│   ├── optimization_service.dart # OTS heuristic & matching algorithm
│   ├── routing_service.dart    # Geospatial OSRM/ORS pathfinding logic
│   ├── simulation_service.dart # Real-time demo data generation engine
│   └── tool_dispatcher.dart    # AI tool-calling & data registry
│
├── views/                      # Presentation Layer (UI)
│   ├── admin/                  # Central Command Module
│   │   ├── admin_indent_approval_page.dart
│   │   ├── admin_indent_status_page.dart
│   │   ├── admin_overview.dart
│   │   └── route_optimization_map.dart
│   │
│   ├── auth/                   # Security & Role Gatekeeping
│   │   ├── login_screen.dart
│   │   └── role_selection_screen.dart
│   │
│   ├── facility/               # Local Management Module
│   │   ├── active_indents_page.dart
│   │   ├── ai_forecast_page.dart
│   │   ├── alerts_page.dart
│   │   ├── daily_logging_page.dart
│   │   ├── facility_overview.dart
│   │   └── indent_creation_page.dart
│   │
│   └── shared/                 # Common & Reusable Components
│       ├── ai_chat_page.dart
│       ├── help_page.dart
│       └── sidebar_layout.dart
│
├── firebase_options.dart       # Cross-platform Firebase configuration
└── main.dart                   # Application entry & Router configuration
```

---

## 📊 Data & Schema
MediTrack AI utilizes a hierarchical Firestore schema designed for high-concurrency performance:
*   **`/facilities`**: Metadata, type (urban/rural), and geospatial coordinates.
*   **`/inventory/{fac_id}/medicines`**: Sub-collection tracking individual batches and live stock levels.
*   **`/requests`**: Global collection for tracking movement, status (Pending/Approved/Fulfilled), and manifest details.

---

## ⚙️ Development & Setup

### Prerequisites
- Flutter SDK (>=3.0.0)
- Firebase Project
- Google AI Studio API Key (Gemini)
- OpenRouteService API Key

### Quick Start
```bash
# 1. Clone & Install
git clone https://github.com/pavsoss/MediFlow.git && cd MediFlow
flutter pub get

# 2. Configure Environment
# Create .env and add:
# GEMINI_API_KEY=your_key
# ORS_API_KEY=your_key

# 3. Run Prototype
flutter run -d chrome --web-renderer html
```

---

## 🗺️ Roadmap
- [ ] **Offline-First Sync**: Native SQLite integration for zero-connectivity environments.
- [ ] **Batch Tracking**: QR-code integration for granular tracking of individual medicine strips.
- [ ] **IoT Cold Chain**: Integration with sensors to track temperature-sensitive vaccines during transit.

---

## 🤝 The Team
Built with ❤️ for the **Google Solution Challenge 2026**.

- [Aarush Yadav]
- [Paavni Bansal]
- [Devansh Rana] 
- [Sharvi Singhal]

---
© 2026 MediTrack AI Team. *Engineering a smarter, healthier supply chain.*
