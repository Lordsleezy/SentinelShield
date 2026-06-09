# Sentinel Prime — Android Companion

React Native + Expo companion app for Sentinel Shield. Senior-friendly UI with Sentinel Prime dark theme and teal accents.

## Features

| Tab | Feature |
|-----|---------|
| **Calls** | Spam call blocker via Android Call Screening API (`RoleManager.ROLE_CALL_SCREENING`) |
| **Apps** | Permission auditor — lists non-system apps with camera, mic, or location access; flags apps with 2+ sensitive permissions |
| **Cleaner** | Clears app cache and temporary files |

## Requirements

- Android 10+ (API 29) for call screening role
- Physical device or emulator with Google Play services for call screening setup

## Development

```bash
cd companion
npm install
npx expo prebuild --platform android   # generates android/ with native module linked
npm run android
```

The native module lives in `modules/sentinel-android/` and is auto-linked via `expo-module.config.json`.

## Build for production

```bash
npx expo prebuild --platform android
cd android && ./gradlew assembleRelease
```

Or use EAS Build:

```bash
npx eas build --platform android
```

## Pairing with Sentinel Shield (Windows)

The Windows desktop app and Android companion share the Sentinel Prime brand. Future releases may sync threat alerts via a shared account; for now they operate independently.
