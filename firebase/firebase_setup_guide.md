# Firebase Setup Guide

This document walks you through creating the Firebase project that powers
the Real-Time Tactical Disaster Simulation Flutter app, and wiring it up to
the rest of the project.

The Flutter app uses:

- **Firebase Authentication** (email/password)
- **Cloud Firestore** with five collections: `users`, `hazards`, `casualties`,
  `ambulances`, `routes`

You only have to do this once. After it is done you can hand `flutterfire`
the rest of the work.

---

## 1. Create the Firebase project

1. Sign in to <https://console.firebase.google.com/>.
2. Click **Add project**.
3. Name it something memorable, e.g. `tactical-disaster-sim`.
4. Disable Google Analytics (you do not need it for this project).
5. Wait until Firebase finishes provisioning, then click **Continue**.

## 2. Enable Authentication

1. In the left rail open **Build -> Authentication**.
2. Press **Get started**.
3. Under **Sign-in method**, enable **Email/Password** and press **Save**.

## 3. Create Cloud Firestore

1. Open **Build -> Firestore Database**.
2. Press **Create database**.
3. Pick the **production** mode (we ship our own rules below).
4. Choose a region close to Nepal, for instance `asia-south1` (Mumbai).
5. Wait until the database is provisioned.

## 4. Install the Firebase CLI and FlutterFire CLI

On Ubuntu:

```bash
# Firebase CLI - via the standalone installer
curl -sL https://firebase.tools | bash

# FlutterFire CLI (requires Flutter already installed - see SETUP.md)
dart pub global activate flutterfire_cli

# Make sure ~/.pub-cache/bin is on PATH
echo 'export PATH="$PATH:$HOME/.pub-cache/bin"' >> ~/.bashrc
source ~/.bashrc
```

Sign in:

```bash
firebase login
```

## 5. Generate `firebase_options.dart`

From the Flutter app folder:

```bash
cd "/home/paribartan-timalsina/Prassiddha Code/tactical_disaster_simulation/flutter_app"
flutterfire configure --project=YOUR_PROJECT_ID
```

`flutterfire configure` will:

- Register an Android and (optionally) iOS app with your Firebase project.
- Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
  into the right folders.
- **Overwrite** `lib/firebase_options.dart` with the real configuration. The
  file currently in the repository is a placeholder with `REPLACE_*` markers.

When the wizard asks which platforms to support, pick **android** (and
optionally **ios**, **web**).

## 6. Deploy the Firestore rules and indexes

The committed rules in `firebase/firestore.rules` enforce the data model from
section 12 of the blueprint. Deploy them:

```bash
cd "/home/paribartan-timalsina/Prassiddha Code/tactical_disaster_simulation/firebase"

# One-time: tell the CLI which Firebase project this folder targets.
firebase use --add YOUR_PROJECT_ID --alias default

# Push rules + indexes.
firebase deploy --only firestore:rules,firestore:indexes
```

## 7. Sanity check

In the Firebase console:

- Authentication -> Users panel should be empty but reachable.
- Firestore -> Rules tab should show the rules you just deployed.
- Firestore -> Indexes tab should show the four composite indexes from
  `firestore.indexes.json`.

Once that is true, launch the Flutter app (`flutter run`), sign up a user,
and then watch the `users` collection populate in real time.

---

## Data model recap

```
users/{uid}
  email:      string
  name:       string
  phone:      string  (10 digits, starts with 97 or 98)
  role:       string  (default "responder")
  createdAt:  timestamp

hazards/{id}
  type:       "forest_fire" | "flood" | "landslide" | "danger_zone"
  lat:        number  (27.45 .. 27.95)
  lng:        number  (85.40 .. 85.95)
  severity:   "low" | "medium" | "high"
  status:     "active" | "cleared"
  reportedBy: string  (uid)
  createdAt:  timestamp

casualties/{id}
  lat:        number
  lng:        number
  status:     "pending" | "dispatched" | "transporting" | "delivered"
  dispatchedAmbulanceId: string | null
  reportedBy: string  (uid)
  createdAt:  timestamp

ambulances/{id}
  lat:        number
  lng:        number
  status:     "available" | "busy"
  hospital:   string
  updatedAt:  timestamp

routes/{id}
  casualtyId:      string
  primary:         [[lat, lng], ...]
  secondary:       [[lat, lng], ...]
  primaryCostKm:   number
  secondaryCostKm: number
  algorithmPrimary:   "astar"
  algorithmSecondary: "dijkstra"
  createdAt:  timestamp
```

That's everything the app needs.
