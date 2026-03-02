# Subscription Tiers & Clips Manager Setup Guide

This document covers everything you need to do before shipping the new subscription system, Clips Manager overhaul, and Imgur upload feature.

---

## 1. App Store Connect — Product IDs

Register three new in-app purchase products in [App Store Connect](https://appstoreconnect.apple.com):

| Product ID | Type | Notes |
|---|---|---|
| `com.refractored.tinyclips.pro.monthly` | Auto-Renewable Subscription | Monthly billing |
| `com.refractored.tinyclips.pro.yearly` | Auto-Renewable Subscription | Yearly billing — shown as "Best Value" in the paywall |
| `com.refractored.tinyclips.pro.lifetime` | Non-Consumable | One-time purchase — shown as "One-Time" in the paywall |

### Steps

1. Go to **App Store Connect → Your App → Subscriptions**
2. Create a **Subscription Group** (e.g., "TinyClips Pro") if one doesn't exist
3. Add the `monthly` and `yearly` products to the subscription group
4. Go to **In-App Purchases** and add the `lifetime` product as a non-consumable
5. Set pricing for each product and add localized display names/descriptions
6. Submit for review (products must be approved before they work in production)

> **Legacy compatibility:** The old `com.refractored.tinyclips.pro` product ID is still checked in `StoreService.swift`. Existing purchasers will retain Pro status. You can eventually deprecate this product in App Store Connect once all users have updated.

---

## 2. StoreKit Testing (Sandbox)

Before shipping, test all purchase flows in the StoreKit sandbox:

1. **Create sandbox test accounts** in App Store Connect → Users and Access → Sandbox Testers
2. **StoreKit Configuration file (recommended):** Create a `.storekit` configuration in Xcode for local testing:
   - File → New → File → StoreKit Configuration File
   - Add matching product IDs for monthly, yearly, and lifetime
   - Set as the active StoreKit Configuration in the scheme (Edit Scheme → Run → Options → StoreKit Configuration)
3. **Test these flows:**
   - [ ] Purchase monthly subscription
   - [ ] Purchase yearly subscription
   - [ ] Purchase lifetime unlock
   - [ ] Restore purchases (existing + new product IDs)
   - [ ] Legacy `com.refractored.tinyclips.pro` purchasers still show as Pro
   - [ ] Subscription expiry/renewal behavior
   - [ ] Paywall UI displays correct prices from StoreKit
   - [ ] "Manage Subscription" link works for active subscribers

---

## 3. Imgur API Registration

The Imgur upload feature requires a registered Client ID.

### Steps

1. Go to [https://api.imgur.com/oauth2/addclient](https://api.imgur.com/oauth2/addclient)
2. Register a new application:
   - **Application name:** TinyClips
   - **Authorization type:** "OAuth 2 authorization without a callback URL" (anonymous uploads only need Client-ID)
   - **Email:** your contact email
3. Copy the **Client ID** from the registered application
4. Replace the placeholder in `TinyClips/Services/ImgurService.swift`:

```swift
// Line 40 — replace this:
private let clientID = "YOUR_IMGUR_CLIENT_ID"

// With your real Client ID:
private let clientID = "abc123yourclientid"
```

### Imgur API Limits

- **Anonymous uploads:** 1,250 uploads/day, 12,500 requests/hour per Client ID
- **Image size limit:** 10 MB
- **Video/GIF size limit:** 200 MB
- These limits are enforced in `ImgurService.swift` with user-friendly error messages

### Testing

- [ ] Upload a screenshot (PNG/JPEG)
- [ ] Upload a GIF
- [ ] Upload a video (MP4)
- [ ] Verify "Copy Imgur Link" works after upload
- [ ] Verify the link is persisted (re-open Clips Manager, right-click → "Copy Imgur Link" still available)
- [ ] Test rate limit error handling

---

## 4. SwiftData Schema Migration

A new optional field `imgurLink: String?` was added to `ClipMetadataRecord`. SwiftData handles lightweight migrations for optional property additions automatically, but this should be verified:

- [ ] Install the **previous version** of TinyClips (before this PR)
- [ ] Create some clips so metadata records exist
- [ ] Update to the **new version** (this PR)
- [ ] Verify existing clips load without errors
- [ ] Verify new clips get the `imgurLink` field (upload to Imgur, confirm it persists)

---

## 5. Pro Gating Verification (App Store Build)

The Clips Manager uses a read-only mode for free users on the App Store build. Verify:

- [ ] Free users can browse and preview all clips
- [ ] Free users see the yellow "Upgrade to TinyClips Pro" banner
- [ ] These actions show the Pro upsell sheet for free users:
  - Rename, Tag, Notes, Favorites, Delete
  - Batch operations (Select mode is hidden)
  - Imgur upload
- [ ] Pro users have full access to all features
- [ ] Direct distribution build (`TinyClips` scheme) has no Pro gating at all

---

## 6. UI Verification

- [ ] **Paywall (`ProSubscriptionView`):** Fits within the Settings window (420×340 frame) — may need scroll view if content overflows
- [ ] **Smart Collections sidebar:** All collections filter correctly (Recent, This Week, This Month, by type, Large Files, Favorites, Has Notes)
- [ ] **Auto-tags:** Display correctly with tertiary style (distinct from user tags)
- [ ] **Toolbar:** Sort & Filter menu works, search bar filters live, batch toolbar appears/disappears with selection mode
- [ ] **Imgur upload:** Progress indicator shows during upload, context menu items appear correctly

---

## Quick Reference

| Item | Location |
|---|---|
| Product IDs | `TinyClips/Services/StoreService.swift` → `ProPlan` enum |
| Imgur Client ID | `TinyClips/Services/ImgurService.swift` line 40 |
| Paywall UI | `TinyClips/Views/SubscriptionView.swift` |
| Clips Manager | `TinyClips/Views/ClipsManagerWindow.swift` |
| Settings Pro tab | `TinyClips/Views/SettingsView.swift` → `ProSettingsSection` |
| SwiftData model | `ClipMetadataRecord` in `ClipsManagerWindow.swift` |
