# Fitbit to Apple Health

An iPhone SwiftUI app that imports supported wellness data from Fitbit's Web API and saves it into Apple Health. It is designed for current Fitbit Inspire devices (including Inspire 3) and does not connect to the tracker over Bluetooth—the Fitbit app first uploads tracker data to Fitbit, then this app imports it from your Fitbit account.

## Setup

1. Open `FitbitHealthSync.xcodeproj` in Xcode 16 or later and choose your development team.
2. Create a Fitbit application at the [Fitbit developer console](https://dev.fitbit.com/apps/new).
3. Set the OAuth 2.0 application type to **Personal** and callback URL to `fitbithealthsync://oauth/callback`.
4. Copy `FitbitHealthSync/Configuration.example.xcconfig` to `FitbitHealthSync/Configuration.xcconfig` and enter the Fitbit client ID. The file is git-ignored.
5. Run on a physical iPhone. HealthKit is not fully available in the Simulator.

## Building and deploying from Windows

Apple requires iPhone apps to be compiled and signed with Xcode on macOS, so the final build cannot run directly on Windows. You **can**, however, do all day-to-day editing from Windows and let the included GitHub Actions workflow rent a temporary macOS runner to build, sign, and upload the app to TestFlight.

### One-time Apple setup

You need a paid Apple Developer Program membership. In Apple Developer and App Store Connect:

1. Register a unique explicit App ID, such as `com.yourname.FitbitHealthSync`, and enable the **HealthKit** capability.
2. Create an App Store distribution certificate and export it with its private key as a password-protected `.p12` file. If you have no access to a Mac for this one-time step, generate the private key and certificate-signing request with OpenSSL on Windows, upload the CSR in the Apple Developer portal, download the certificate, and combine it with that same private key into a `.p12`.
3. Create and download an **App Store** provisioning profile for that App ID and certificate.
4. Create the app record in App Store Connect using exactly the same bundle ID.
5. Under **Users and Access → Integrations**, create an App Store Connect API key with permission to upload builds and download its `.p8` file. Apple lets you download this file only once.

Keep certificates, private keys, profiles, and API keys private. Never commit them to this repository.

### Add GitHub repository secrets

In GitHub, open **Settings → Secrets and variables → Actions** and create these repository secrets:

| Secret | Value |
| --- | --- |
| `APP_BUNDLE_ID` | The explicit App ID, for example `com.yourname.FitbitHealthSync` |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer team ID |
| `CERTIFICATE_P12_BASE64` | Base64 text of the distribution `.p12` |
| `CERTIFICATE_PASSWORD` | Password used when exporting/creating the `.p12` |
| `PROVISIONING_PROFILE_BASE64` | Base64 text of the `.mobileprovision` file |
| `FITBIT_CLIENT_ID` | Client ID from your Fitbit developer application |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_API_ISSUER` | App Store Connect API issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Base64 text of the downloaded `.p8` API key |

In PowerShell, create the required single-line Base64 values with:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\distribution.p12"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\profile.mobileprovision"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\AuthKey_ABC123.p8"))
```

### Build from the GitHub website

1. Push this repository to GitHub from Windows.
2. Open **Actions → Build and release iPhone app → Run workflow**.
3. Leave **Upload to TestFlight** enabled for the easiest installation path.
4. After Apple processes the build, open the TestFlight app on the iPhone and install it. Add yourself as an internal tester in App Store Connect if needed.

The workflow also saves the signed IPA as a short-lived GitHub Actions artifact. TestFlight is recommended because downloading an IPA on Windows does not by itself install it on an iPhone; iOS still verifies the signature and provisioning when installing. The workflow uses its GitHub run number as the app build number so later TestFlight uploads remain unique.

The app requests only read access from Fitbit and write access to Apple Health. OAuth tokens are stored in the iOS Keychain. Re-imports are safe: imported samples carry a stable Fitbit identifier and are de-duplicated before being saved.

## Supported data

- Steps, walking/running distance, active energy, and resting energy
- Heart rate and resting heart rate
- Sleep sessions
- Weight, body-fat percentage, and water
- Blood oxygen saturation, respiratory rate, heart-rate variability, and wrist temperature when returned by Fitbit and supported by the installed iOS version

Fitbit API access and available measurements vary by device, account, region, and Fitbit approval. Apple Health does not expose a general-purpose destination for every Fitbit field, so unsupported fields are intentionally not written.

## Privacy

Health data stays on the phone and is sent only between Fitbit and HealthKit. This sample has no analytics or backend. Before shipping, add your own privacy policy, App Store privacy disclosures, Fitbit production approval, and user-facing support details.
