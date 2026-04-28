# MediFlow: Advanced AI-Driven Healthcare Logistics & Supply Chain Optimization

<p align="center">
  <img src="https://img.shields.io/badge/Status-Production--Ready-success?style=for-the-badge" alt="Status">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Firebase-Backend-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" alt="Firebase">
  <img src="https://img.shields.io/badge/Gemini-1.5--Flash-4285F4?style=for-the-badge&logo=google-gemini&logoColor=white" alt="Gemini AI">
</p>

---

## 📖 Table of Contents
- [Project Overview](#-project-overview)
- [The Problem & Solution](#-the-problem--the-solution)
- [Core Feature Set](#-core-feature-set)
  - [Hospital/Facility Module](#-hospitalfacility-module)
  - [Central Administration Module](#-central-administration-module)
- [Technical Architecture](#-technical-architecture)
  - [The AI Engine (Gemini 1.5 Flash)](#1-the-ai-engine-gemini-15-flash)
  - [The Optimization Heuristic (OTS)](#2-the-optimization-heuristic-ots)
  - [Geospatial Routing System](#3-geospatial-routing-system)
- [Data & Schema](#-data--schema)
- [Development & Setup](#-development--setup)
- [Roadmap](#-roadmap)

---

## 🌟 Project Overview
**MediFlow** is an enterprise-grade medical logistics platform engineered to solve the "Last Mile" medical supply crisis. By combining **Generative AI** for demand forecasting with **Heuristic Optimization** for redistribution, MediFlow transforms a fragmented, reactive supply chain into a proactive, life-saving ecosystem.

## ⚠️ The Problem | The Solution
**The Crisis:** Rural clinics often face 30% higher stockout rates for essential antibiotics, while urban hospitals simultaneously dispose of expired stock due to over-purchasing.
**The MediFlow Fix:** We don't just track inventory; we **predict** shortages before they happen and **automate** the movement of medicine from surplus hospitals to deficit clinics using road-accurate route optimization.

---

## 🚀 Core Feature Set

### 🏥 Hospital/Facility Module
*   **Smart Logging Engine**: Atomically track daily usage while the system computes burn rates in real-time.
*   **AI Forecasting (30-Day)**: Powered by **Gemini-1.5-Flash**, predicting seasonal spikes (e.g., ORS demand for summer) with a transparency-first "AI Reasoning" component.
*   **Automated Request Drafting**: Intelligent auto-population of restock indents and redistribution offers based on AI predictions.
*   **AI Chat Assistant**: A 24/7 logistics expert that facility managers can query for stock status, expiry alerts, or burn-rate insights.

### 🏢 Central Administration Module
*   **Global Command Center**: Real-time regional oversight with deep-dive analytics into every facility's stock health.
*   **Multi-Step Approval Pipeline**: A secure hub for regional admins to review and prioritize redistribution plans.
*   **Interactive Logistics Map**: 
    *   **Donors vs. Recipients**: High-visibility markers distinguishing surplus sites from deficit clinics.
    *   **Road-Accurate Routing**: Integrated OSRM/ORS paths that calculate real-world travel time and distance.
*   **Global Optimization**: A "Global Redistribution Plan" that matches thousands of shortage items to local surpluses in seconds.

---

## 🏛️ Technical Architecture

MediFlow is built on **Clean Architecture** principles, ensuring that business logic is decoupled from the UI and external services.

### 1. The AI Engine (Gemini 1.5 Flash)
We leverage Gemini's large context window to process months of anonymized usage logs. The model acts as a **Predictive Reasoning Layer**, identifying non-obvious patterns like demographic-based medicine consumption surges.

### 2. The Optimization Heuristic (OTS)
Our proprietary **Optimal Transfer Score** ensures that redistribution is both efficient and equitable:
$$OTS = (w_{dist} \cdot Proximity) + (w_{prior} \cdot RuralPriority) + (w_{qty} \cdot QtyMatch)$$
*   **Proximity**: Minimizes logistics cost and time.
*   **Rural Priority**: A weight multiplier ensuring that remote facilities are never "starved" by the algorithm.

### 3. Geospatial Routing System
Integrated with **flutter_map** and **OSRM/OpenRouteService**, our routing engine decodes complex polylines to provide precise, road-accurate delivery paths, factoring in real-world geography rather than simple straight lines.

---

## 📊 Data & Schema
MediFlow utilizes a hierarchical Firestore schema designed for high-concurrency performance:
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
Built with ❤️ for the **Google Gemini AI Hackathon**.

**Lead Engineers**:
- [Aarush Yadav](https://github.com/aarushyadav)
- [Paavni](https://github.com/paavni)

---
© 2026 MediFlow Team. *Engineering a smarter, healthier supply chain.*
