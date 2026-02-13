# Sparkle Auto-Updates Setup Guide

This document describes the manual setup steps required to enable Sparkle auto-updates for TinyClips.

## Prerequisites

- Xcode 16+
- Apple Developer ID certificate
- GitHub repository with Actions enabled

## Step 1: Add Sparkle via Swift Package Manager (REQUIRED)

**⚠️ IMPORTANT: Sparkle must be added via Xcode's UI. The package reference is NOT included in the repository.**

1. Open `TinyClips.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter URL: `https://github.com/sparkle-project/Sparkle`
4. Select version rule: **Up to Next Major Version** from `2.8.1`
5. Click **Add Package**
6. In the dialog, select `Sparkle` framework for the `TinyClips` target
7. Click **Add Package**

### Verify Sparkle Integration

After adding, ensure:
- The Sparkle framework appears in your project's **Frameworks, Libraries, and Embedded Content**
- In Project Navigator, you should see **Package Dependencies** with Sparkle listed
- Build the project to verify no linking errors

### Why Manual Addition?

Xcode's project file format is complex and version-specific. Adding SPM packages programmatically can cause project corruption. Adding via Xcode's UI ensures proper integration with your specific Xcode version.

## Step 2: Generate Sparkle Keys

Sparkle uses EdDSA (Ed25519) signatures for security. Generate your key pair:

### Using Sparkle's generate_keys Tool

1. After adding Sparkle via SPM, find the tools in:
   - In Xcode, expand **Package Dependencies → Sparkle**
   - Right-click and **Show in Finder**
   - Navigate to `artifacts/sparkle/Sparkle/bin/`

2. Generate keys:
   ```bash
   cd /path/to/Sparkle/bin
   ./generate_keys
   ```

3. The tool will:
   - Generate a new private/public key pair
   - Store the private key in your Keychain (Sparkle Private Key)
   - Display the **public key** — copy this for Info.plist

4. **Backup your private key** (IMPORTANT):
   ```bash
   ./generate_keys -x ~/Desktop/sparkle_private_key.txt
   ```
   Store this backup securely — you cannot recover it if lost!

### Add Public Key to Info.plist

Replace the placeholder `SUPublicEDKey` value in `TinyClips/Info.plist` with your actual public key.

## Step 3: Configure GitHub Secrets

Add these secrets to your GitHub repository (**Settings → Secrets and variables → Actions**):

### Required Secrets

| Secret Name | Description | How to Get |
|------------|-------------|------------|
| `SPARKLE_PRIVATE_KEY` | Full contents of exported private key file | From `./generate_keys -x` output |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded Developer ID certificate (.p12) | Export from Keychain, then `base64 -i certificate.p12` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the .p12 certificate | Set when exporting |
| `KEYCHAIN_PASSWORD` | Any strong password for temporary keychain | Generate a random password |
| `APPLE_ID` | Your Apple ID email | Your Apple Developer account email |
| `APP_PASSWORD` | App-specific password | Generate at [appleid.apple.com](https://appleid.apple.com) → Security → App-Specific Passwords |
| `APPLE_TEAM_ID` | Your Apple Developer Team ID | Find in [developer.apple.com](https://developer.apple.com) → Membership |

### Creating the Developer ID Certificate

1. Open **Keychain Access**
2. Find your **Developer ID Application** certificate
3. Right-click → **Export**
4. Save as `.p12` with a strong password
5. Convert to base64:
   ```bash
   base64 -i DeveloperID.p12 | pbcopy
   ```
6. Paste into GitHub secret `DEVELOPER_ID_CERTIFICATE_BASE64`

### Creating App-Specific Password

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in → **Security** section
3. Under **App-Specific Passwords**, click **Generate Password**
4. Name it "TinyClips Notarization"
5. Copy the generated password to `APP_PASSWORD` secret

## Step 4: Enable GitHub Pages

1. Go to repository **Settings → Pages**
2. Under **Source**, select:
   - Branch: `main`
   - Folder: `/docs`
3. Click **Save**
4. Wait for deployment (may take a few minutes)
5. Verify appcast is accessible at:
   `https://jamesmontemagno.github.io/tiny-clips-mac/appcast.xml`

## Step 5: Create a Release

To trigger the workflow and create a release:

```bash
# Tag a version
git tag v1.0.0
git push origin v1.0.0
```

The GitHub Action will:
1. Build the app with Release configuration
2. Sign with Developer ID certificate
3. Notarize with Apple
4. Create a signed ZIP
5. Generate the appcast.xml with Sparkle tools
6. Create a GitHub Release with the artifacts
7. Deploy appcast to GitHub Pages

## Version Numbering

- `CFBundleShortVersionString` (Marketing Version): `1.0.0`, `1.0.1`, `1.1.0`
- `CFBundleVersion` (Build Number): Auto-incremented by CI via `github.run_number`

Sparkle compares versions semantically. Use standard semver format.
