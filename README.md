# MediFlow: AI-Powered Medical Supply Chain Optimization

![MediFlow Logo](https://img.shields.io/badge/Status-Prototype-blueviolet?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![Gemini AI](https://img.shields.io/badge/Gemini%20AI-4285F4?style=for-the-badge&logo=google&logoColor=white)

MediFlow is a next-generation medical logistics platform designed to eliminate medicine wastage and prevent critical stockouts in healthcare networks. By leveraging **Google Gemini AI** and **Advanced Route Optimization**, MediFlow transforms a reactive supply chain into a proactive, intelligent ecosystem.

## 🚀 The Vision
Every year, essential medicines worth billions expire in urban centers while rural clinics face life-threatening shortages. MediFlow bridges this gap by intelligently predicting demand and facilitating the automated redistribution of medical supplies from areas of surplus to areas of deficit.

---

## ✨ Key Features

### 1. **AI-Driven Demand Forecasting**
- **Predictive Analytics**: Utilizes Gemini-1.5-Flash to analyze historical usage, seasonal trends, and demographic profiles.
- **Proactive Buffering**: Automatically suggests stock adjustments for upcoming spikes (e.g., predicting dehydration trends to increase ORS supply for summer).

### 2. **Smart Redistribution Engine**
- **Automated Matching**: Instantly identifies facilities with excess stock and matches them with those in need.
- **Redistribution Requests**: Automated generation of redistribution offers and restock requests, reducing manual paperwork by 80%.

### 3. **Dynamic Route Optimization**
- **Road-Accurate Routing**: Integrated with OSRM and OpenRouteService (ORS) to generate the most efficient delivery paths.
- **Rural Priority Scoring**: A proprietary scoring algorithm that prioritizes life-saving deliveries to remote and underserved areas.

### 4. **Intelligent Inventory Command Center**
- **Real-time Alerts**: Instant notifications for low stock, critical shortages, and near-expiry batches.
- **AI Chat Assistant**: A natural language interface for facility managers and administrators to query complex logistics data.

---

## 🛠️ Tech Stack

- **Framework**: [Flutter](https://flutter.dev/) (Multi-platform support)
- **State Management**: [Riverpod](https://riverpod.dev/)
- **Navigation**: [GoRouter](https://pub.dev/packages/go_router)
- **Backend**: [Firebase](https://firebase.google.com/) (Firestore for real-time data, Firebase Auth)
- **AI/LLM**: [Google Generative AI (Gemini)](https://ai.google.dev/)
- **Maps & GIS**: [Flutter Map](https://pub.dev/packages/flutter_map) & [LatLong2](https://pub.dev/packages/latlong2)
- **API**: [OpenRouteService](https://openrouteservice.org/)

---

## 📂 Project Structure

```bash
lib/
├── models/          # Data schemas (Facility, Request, Inventory)
├── services/        # Business logic (AI, Routing, Optimization, Firebase)
├── views/           # UI Layer
│   ├── admin/       # Central Management interfaces
│   ├── facility/    # Local Clinic/Hospital dashboards
│   └── shared/      # Common components (AI Chat, Help, Sidebar)
├── constants/       # Design tokens (Colors, Typography)
└── main.dart        # Application entry and routing configuration
```

---

## ⚙️ Getting Started

### Prerequisites
- Flutter SDK (>=3.0.0)
- Firebase Account
- Google AI Studio API Key (for Gemini)
- OpenRouteService API Key (for maps)

### Installation
1. **Clone the repository:**
   ```bash
   git clone https://github.com/pavsoss/MediFlow.git
   ```
2. **Configure Environment:**
   Create a `.env` file in the root directory and add your keys:
   ```env
   GEMINI_API_KEY=your_gemini_key
   ORS_API_KEY=your_ors_key
   ```
3. **Install dependencies:**
   ```bash
   flutter pub get
   ```
4. **Run the application:**
   ```bash
   flutter run
   ```

---

## 🛡️ Security & Scalability
- **Role-Based Access Control (RBAC)**: Distinct workflows for Facility Managers and Central Administrators.
- **Real-time Synchronization**: Powered by Firestore listeners for zero-latency supply chain updates.
- **Scalable Architecture**: Modular service-oriented design ready for enterprise-level deployment.

---

## 🤝 Acknowledgments
Built for the **Google Gemini AI Hackathon**, focusing on sustainable healthcare logistics and technological equity.

---
© 2026 MediFlow Team. Transforming healthcare logistics for a healthier world.
