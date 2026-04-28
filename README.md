# MediFlow: AI-Driven Smart Resource Allocation for Healthcare Equity

---

## 📖 Table of Contents
- [Project Overview](#-project-overview)
- [The Problem & Solution](#-the-problem--the-solution)
- [Core Feature Set](#-core-feature-set)
  - [Facility Intelligence Module](#-facility-intelligence-module)
  - [Central Resource Command](#-central-resource-command)
- [Technical Architecture](#-technical-architecture)
  - [Demand Intelligence (Gemini 1.5 Flash)](#1-demand-intelligence-gemini-15-flash)
  - [Heuristic Allocation Engine (OTS)](#2-heuristic-allocation-engine-ots)
  - [Dynamic Routing System](#3-dynamic-routing-system)
- [Data & Schema](#-data--schema)
- [Development & Setup](#-development--setup)
- [Roadmap](#-roadmap)

---

## 🌟 Project Overview
**MediFlow** is a specialized healthcare intelligence platform designed to achieve **Smart Resource Allocation** across complex medical networks. By integrating **Gemini-1.5-Flash** for predictive demand modeling and advanced heuristics for inventory balancing, MediFlow ensures that life-saving resources are distributed based on actual need and clinical priority, rather than static supply-chain cycles.

## ⚠️ The Problem | The Strategic Solution
**The Crisis:** Healthcare systems suffer from deep-seated **resource inequality**. Urban centers often hold 40% more stock than required, leading to critical wastage, while rural facilities face frequent "zero-stock" days for life-saving antibiotics and vaccines.
**The MediFlow Solution:** We move beyond traditional supply chain management to **Dynamic Resource Balancing**. Our system predicts where resources *will be* needed and intelligently re-allocates existing stock within the network—bridging the gap between surplus and scarcity in real-time.

---

## 🚀 Core Feature Set

### 🏥 Facility Intelligence Module
*   **Predictive Demand Modeling (30-Day)**: Uses Gemini AI to forecast resource needs by analyzing burn rates, local health trends, and seasonal spikes.
*   **Smart Resource Alerts**: Automated triggers for low-resource states and expiration risks, enabling local managers to take proactive action.
*   **Automated Allocation Requests**: AI-generated drafts for resource replenishment or surplus offers to support the wider network.
*   **Clinical Assistant (Chat)**: A natural language interface providing instant insights into resource burn rates and stock health.

### 🏢 Central Resource Command
*   **Network Equity Dashboard**: A unified view for regional administrators to monitor resource parity across all urban and rural nodes.
*   **Intelligent Balancing Hub**: A centralized pipeline for reviewing and approving resource transfers between facilities.
*   **Active Allocation Map**: 
    *   **Resource Mapping**: Visualizing surpluses and deficits geographically to identify regional clusters of need.
    *   **Dynamic Routing**: Real-time road-accurate pathing for the physical movement of re-allocated stock.
*   **Global Optimization Engine**: One-click system-wide balancing that matches thousands of shortage items to available local surpluses in seconds.

---

## 🏛️ Technical Architecture

### 1. Demand Intelligence (Gemini 1.5 Flash)
Gemini acts as the **Clinical Reasoning Layer**, processing multi-modal usage data to identify non-linear demand patterns. It doesn't just predict volume; it provides the clinical context behind every allocation recommendation.

### 2. Heuristic Allocation Engine (OTS)
Our proprietary **Optimal Transfer Score (OTS)** prioritizes resource equity:
$$OTS = (w_{dist} \cdot Proximity) + (w_{prior} \cdot RuralPriority) + (w_{qty} \cdot QtyMatch)$$
*   **Rural Priority**: An equity-weight multiplier that ensures underserved facilities are prioritized in the allocation queue.

### 3. Dynamic Routing System
Integrated with **OSRM/OpenRouteService**, our routing engine ensures that the physical movement of re-allocated resources follows the most efficient, road-accurate paths possible.

---

## 📊 Data & Schema
*   **`/facilities`**: Node metadata and geospatial clinical profiles.
*   **`/inventory/{fac_id}/medicines`**: Live resource tracking with atomic depletion logs.
*   **`/requests`**: The ledger of resource movement and system-wide balancing.

---

## ⚙️ Development & Setup

### Quick Start
```bash
# 1. Clone & Install
git clone https://github.com/pavsoss/MediFlow.git && cd MediFlow
flutter pub get

# 2. Configure Environment (.env)
GEMINI_API_KEY=your_key
ORS_API_KEY=your_key

# 3. Run Prototype
flutter run -d chrome --web-renderer html
```

---

## 🗺️ Roadmap
- [ ] **Regional Cluster Analysis**: Using AI to detect regional disease outbreaks through resource burn-rate anomalies.
- [ ] **Predictive Procurement**: Linking regional allocation data directly to bulk procurement systems for cost-savings.

---

## 🤝 The Team
Built with ❤️ for the **Google Gemini AI Hackathon**.

- [Aarush Yadav](https://github.com/aarushyadav)
- [Paavni](https://github.com/paavni)
- [Devansh Rana](https://github.com/devanshrana)
- [Sharvi Singhal](https://github.com/sharvisinghal)

---
© 2026 MediFlow Team. *Engineering healthcare equity through smart resource allocation.*
