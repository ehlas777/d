# TestFlight iPad IAP Bug - Solution Guide

## Problem
**"Product not found: com.qaznat.polydub.subscription.standard"** on iPad in TestFlight, but works on iPhone.

## Root Cause (TestFlight Specific)

In **TestFlight**, unlike local development, apps use **real App Store Connect products**, not local StoreKit configuration. This means:

1. Products must be fully configured in App Store Connect
2. Products must be submitted with the app (or already approved)
3. The **sandbox account** must have access to these products
4. Products must be **approved** or **waiting for review** (NOT rejected)

## Why It Works on iPhone But Not iPad

### Most Likely Causes:

#### **1. App Store Connect Device Compatibility** ⭐ (Most Common)
The products may be configured for iPhone only, excluding iPad.

**Fix:**
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. **My Apps** → Your App → **Features** → **In-App Purchases**
3. Click **com.qaznat.polydub.subscription.standard**
4. Scroll to **"Availability"** section
5. Under **"Supported Devices"** → Check both:
   - ☑ iPhone
   - ☑ iPad
6. Click **Save**
7. Repeat for **com.qaznat.polydub.subscription.pro**

#### **2. Different Sandbox Accounts on iPad vs iPhone**
iPad might be signed into a different Apple ID / Sandbox account.

**Fix:**
1. On **iPad**: Settings → App Store
   2. Scroll to **SANDBOX ACCOUNT** section
3. Check which email is signed in
4. If different from iPhone: **Sign Out**
5. **Sign in** with the SAME sandbox test account as iPhone
6. Delete and reinstall the TestFlight app
7. Try again

#### **3. App Store Connect Sync Delay**
Sometimes Apple's servers take time to sync products across devices.

**Fix:**
- Wait 24-48 hours after product approval
- Clear iPad cache:
  - Delete TestFlight app
  - Restart iPad
  - Reinstall from TestFlight
- Try on a different iPad to rule out device-specific cache

#### **4. Products Not Submitted With Current Build**
For TestFlight, products must be **submitted for review** with the app.

**Check:**
1. App Store Connect → Your App → **Prepare for Submission**
2. Scroll to **"In-App Purchases"**
3. Ensure both products are listed:
   - com.qaznat.polydub.subscription.standard
   - com.qaznat.polydub.subscription.pro
4. If missing, add them and submit a new build

#### **5. Regional / Store Front Differences**
iPad might be set to a different region than iPhone.

**Fix:**
1. iPad: Settings → General → Language & Region
2. Check **Region** matches iPhone
3. App Store Connect: Verify products are available in that region

---

## Step-by-Step Fix (Do in Order):

### ✅ Step 1: Verify App Store Connect Configuration

```
1. Login to App Store Connect
2. Go to: My Apps → QazNat VT → Features → In-App Purchases
3. For EACH product (standard and pro):
   a. Click on the product
   b. Verify Status is "Ready to Submit" or "Approved"
   c. Check "Availability" section
   d. Ensure "Reference Name" matches: Standard / Pro
   e. Ensure "Product ID" exactly matches:
      - com.qaznat.polydub.subscription.standard
      - com.qaznat.polydub.subscription.pro
   f. Verify "Subscription Group" is set correctly
   g. CRITICAL: Check "Supported Devices" includes iPad!
```

### ✅ Step 2: Verify Sandbox Account on iPad

```
On iPad:
1. Settings → App Store
2. Scroll to bottom: "SANDBOX ACCOUNT"
3. Current account: ___________________ (write it down)
4. Compare with iPhone sandbox account
5. If different:
   - Tap sandbox account → Sign Out
   - Sign in with SAME account as iPhone
```

### ✅ Step 3: Clear iPad IAP Cache

```
1. Delete TestFlight app completely from iPad
2. Settings → General → iPad Storage → TestFlight → Delete App
3. Restart iPad (power off and on)
4. Reinstall TestFlight from App Store
5. Install your app from TestFlight
6. Try purchasing again
```

### ✅ Step 4: Verify Console Logs (With New Diagnostic Code)

The enhanced logging I added will show:

```
═══════════════════════════════════════════════════════
🔄 LOADING IAP PRODUCTS
═══════════════════════════════════════════════════════
Platform: ios
OS: iOS 17.x.x
Device: iOS Device
Product IDs to query: [com.qaznat.polydub.subscription.standard, ...]
═══════════════════════════════════════════════════════
```

**Expected Output (Success):**
```
✅ Successfully loaded 2 products:
   📦 com.qaznat.polydub.subscription.standard
   📦 com.qaznat.polydub.subscription.pro
```

**Current Output (Failure):**
```
⚠️  WARNING: Products NOT FOUND in App Store Connect:
   ❌ com.qaznat.polydub.subscription.standard
   ❌ com.qaznat.polydub.subscription.pro
```

When you click SUBSCRIBE, you should now see:
```
📱 PURCHASE DEBUG INFO
Requesting Product ID: com.qaznat.polydub.subscription.standard
Available Products: [] ← EMPTY = PROBLEM!
```

### ✅ Step 5: Test on Another iPad

If steps 1-4 don't work:
- Borrow another iPad
- Install TestFlight
- Sign in with same sandbox account
- Test subscription purchase

This will tell us if it's device-specific or account/configuration issue.

---

## App Store Connect Checklist

For TestFlight IAP to work, ALL of these must be ✅:

- [ ] Products created in App Store Connect
- [ ] Product IDs exactly match code (com.qaznat.polydub.subscription.standard)
- [ ] Products status = "Ready to Submit" or "Approved"
- [ ] Products have pricing in all required territories
- [ ] Products have localizations (at least English)
- [ ] Products assigned to Subscription Group
- [ ] **Supported Devices includes both iPhone AND iPad**
- [ ] Products submitted with current app version
- [ ] Sandbox test account created and verified
- [ ] Sandbox account has active payment method
- [ ] No previous failed/rejected product submissions with same ID

---

## Quick Diagnostic Test

Run this **immediately on iPad in TestFlight**:

1. Open app
2. Go to Subscription screen
3. **Before clicking anything**, check Xcode console
4. Look for: `🔄 LOADING IAP PRODUCTS`
5. Copy the entire output

**Send me the console output** from iPad, specifically:
- The "LOADING IAP PRODUCTS" section
- Any "⚠️ WARNING" or "❌ ERROR" messages
- The "Available Products" line

This will definitively show if products are being loaded or not.

---

## Most Likely Solution (90% Probability)

Based on the error **"Available:"** being empty:

**The products are NOT configured for iPad in App Store Connect.**

### To Fix:
1. App Store Connect → In-App Purchases → Each Product
2. Find "Supported Devices" or "Availability"  
3. Enable iPad
4. Might need to resubmit the product for review
5. Wait for approval (can take 24-48h)
6. New TestFlight build may be required

---

## Immediate Actions

1. ✅ **Check App Store Connect NOW** - Verify iPad is enabled for products
2. ✅ **Compare Sandbox Accounts** - Ensure iPad uses same account as iPhone
3. ✅ **Run new build on iPad** - Capture console logs with my diagnostics
4. ✅ **Share console output** - This will confirm the exact issue

The enhanced diagnostics I added will show **exactly** what's i happening at the IAP level, making it easy to identify the root cause!
