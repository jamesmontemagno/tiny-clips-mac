# Subscription Tiers & Clips Manager Setup Guide

This document covers what you need to do before shipping the subscription system and Clips Manager updates.

---

## 1. App Store Connect — Product IDs

Register three in-app purchase products in [App Store Connect](https://appstoreconnect.apple.com):

| Product ID | Type | Notes |
|---|---|---|
| `com.refractored.tinyclips.pro.monthly` | Auto-Renewable Subscription | Monthly billing |
| `com.refractored.tinyclips.pro.yearly` | Auto-Renewable Subscription | Yearly billing |
| `com.refractored.tinyclips.pro.lifetime` | Non-Consumable | One-time purchase |

### Steps

1. Go to **App Store Connect → Your App → Subscriptions**
2. Create a **Subscription Group** (for monthly/yearly) if needed
3. Add `monthly` and `yearly` to the subscription group
4. Add `lifetime` under **In-App Purchases** as non-consumable
5. Set pricing and localized metadata
6. Submit products for review

---

## 2. StoreKit Testing (Sandbox)

Before shipping, test all purchase flows:

1. Create sandbox tester accounts in App Store Connect
2. Optionally create a local `.storekit` configuration file in Xcode with the same product IDs
3. Verify:
   - [ ] Purchase monthly subscription
   - [ ] Purchase yearly subscription
   - [ ] Purchase lifetime unlock
   - [ ] Restore purchases (monthly/yearly/lifetime)
   - [ ] Subscription renewal/expiry behavior
   - [ ] Paywall pricing displays correctly
   - [ ] Manage subscription link works for active subscribers

---

## 3. Pro Gating Verification (App Store Build)

The Clips Manager uses read-only mode for free users:

- [ ] Free users can browse and preview clips
- [ ] Free users see upgrade banner/upsell prompts
- [ ] Rename/Tag/Notes/Favorites/Delete/Batch actions are gated
- [ ] Pro users have full organization features
- [ ] Direct distribution build has no Pro gating

---

## 4. UI Verification

- [ ] `ProSubscriptionView` fits in Settings window
- [ ] Smart collections and tags sidebar filtering works
- [ ] Auto-tags render with tertiary style (distinct from user tags)
- [ ] Sort & Filter menu + search + list/grid toggle behave correctly
- [ ] Grid/list layouts remain stable at narrow widths

---

## Quick Reference

| Item | Location |
|---|---|
| Product IDs | `TinyClips/Services/StoreService.swift` (`ProPlan`) |
| Paywall UI | `TinyClips/Views/SubscriptionView.swift` |
| Clips Manager | `TinyClips/Views/ClipsManagerWindow.swift` |
| Settings Pro tab | `TinyClips/Views/SettingsView.swift` (`ProSettingsSection`) |
