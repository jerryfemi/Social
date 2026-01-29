# Social Chat App 💬

A production-grade Flutter chat application built with a **local-first architecture**. This project combines a custom "Liquid Glass" UI aesthetic with a robust backend infrastructure using Firebase and Hive for offline capabilities.

Screen Recording: https://drive.google.com/drive/folders/1FUzFNTzfIxn1GMWzGZBtV9otFmIRRT8R

## 📱 Screenshots

<div style="display: flex; overflow-x: auto; gap: 15px; padding-bottom: 10px;">
  <img src="screenshots/homscreen.jfif" height="500" alt="Home Screen" />
  <img src="screenshots/chatscreen.jfif" height="500" alt="Chat Main" />
  <img src="screenshots/chatscreen_1.jfif" height="500" alt="Chat Flow 1" />
  <img src="screenshots/chatscreen2.jfif" height="500" alt="Chat Flow 2" />
  <img src="screenshots/chatscreen3.jfif" height="500" alt="Chat Flow 3" />
</div>

## ✨ Key Features

* **🎨 Liquid Glass UI:** Custom-built glassmorphism implemented on the Navigation Bar, Send Button, and Voice Record Button. The UI uses dynamic blurs and semi-transparent gradients to create a modern, depth-based aesthetic.
* **💾 Local-First Architecture:** Implemented using **Hive** for immediate local storage, ensuring the app feels instant and works fully offline, while syncing with **Cloud Firestore** in the background.
* **🔗 Smart Link Previews:**
    * **Custom Scraper:** Replaced standard packages with a custom implementation using `metadata_fetch` to handle OpenGraph data.
    * **Bot Bypass:** Added custom `User-Agent` headers to successfully fetch metadata from "hard-to-scrape" sites like Instagram, Reddit, and Spotify.
* **🎤 Rich Messaging:**
    * **Voice Notes:** Integrated audio recording and playback with visual waveforms.
    * **Smart Parsing:** Utilizing `flutter_linkify` to detect URLs and emails within text streams.
    * **Media Sharing:** Image and file sharing backed by **Firebase Storage**.
* **🔔 Notifications:** Full integration of **FCM (Firebase Cloud Messaging)** and **Flutter Local Notifications** for background and foreground alerts.

## 🛠️ Tech Stack & Architecture

* **Framework:** Flutter & Dart
* **State Management:** Riverpod (ConsumerWidgets & Providers for reactive state)
* **Navigation:** GoRouter (Deep linking support & type-safe routing)
* **Local Database:** Hive (NoSQL, fast key-value storage)
* **Backend (Firebase):**
    * **Authentication:** Firebase Auth
    * **Database:** Cloud Firestore
    * **Storage:** Firebase Storage (Media & Profile Pictures)
    * **Push Notifications:** Firebase Cloud Messaging (FCM)
* **Core Utilities:**
    * `metadata_fetch` (Custom implementation for link previews)
    * `flutter_linkify` (Text parsing)
    * `url_launcher` (External navigation)

## 🤖 Development Methodology (AI-Native)

This project leverages an **AI-Native workflow** to accelerate development cycles. I utilized LLMs (Gemini) as a pair programmer to:
1.  **Architect Complexity:** Design the data flow between Hive (local) and Firestore (remote) to ensure data consistency.
2.  **Debug Platform Issues:** Resolve CORS restrictions on web builds and optimize image caching strategies.
## 🚀 Getting Started

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/jerryfemi/Social.git](https://github.com/jerryfemi/Social.git)
    ```
2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```
3.  **Setup Firebase:**
    * Add your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) to the respective directories.
4.  **Run the app:**
    ```bash
    flutter run
    ```
