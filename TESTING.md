# Testing ReadIO on Your iPhone

## Quick Overview
The GitHub Actions workflow builds a **simulator-only** `.app` bundle by default. To test on a **real iPhone**, you need to set up code signing.

## Option 1: Download Simulator Build (Current)
1. Go to [GitHub Actions](https://github.com/PossiblyPengu/ReadIO/actions)
2. Click on the latest successful build
3. Download the **ReadIO-simulator-app** artifact
4. This is a simulator build only — won't work on real devices

## Option 2: Test on Real iPhone (Requires Setup)

### Prerequisites
- **Apple Developer Account** (free or paid)
- **Mac with Xcode** (to sign and install)
- **iPhone with iOS 26+** (or iOS 18+ if you lower deployment target)

### Steps to Enable Device Testing

#### 1. Set Up Code Signing Secrets
You need to add these secrets to your GitHub repository:

**Required Secrets** (Settings → Secrets and variables → Actions):
- `IOS_CERTIFICATE_P12` - Base64-encoded signing certificate
- `IOS_CERTIFICATE_PASSWORD` - Certificate password
- `IOS_PROVISIONING_PROFILE` - Base64-encoded provisioning profile
- `IOS_TEAM_ID` - Your Apple Team ID

**How to get these:**

```bash
# Export certificate from Keychain (on Mac)
# 1. Open Keychain Access
# 2. Find your "Apple Development" certificate
# 3. Right-click → Export as .p12
# 4. Set a password

# Base64 encode it
base64 -i Certificate.p12 | pbcopy

# Get provisioning profile
# 1. Go to developer.apple.com
# 2. Certificates, Identifiers & Profiles → Profiles
# 3. Create/download iOS App Development profile
# 4. Base64 encode it:
base64 -i YourProfile.mobileprovision | pbcopy
```

#### 2. Update project.yml
Add your Team ID:
```yaml
targets:
  ReadIO:
    settings:
      DEVELOPMENT_TEAM: YOUR_TEAM_ID_HERE
      CODE_SIGN_STYLE: Manual
      PROVISIONING_PROFILE_SPECIFIER: YOUR_PROFILE_NAME
```

#### 3. Add Device Build Job to Workflow
Uncomment or add this job to `.github/workflows/build.yml`:

```yaml
  build-device:
    name: Build ReadIO for Device
    runs-on: macos-15
    if: github.ref == 'refs/heads/main'
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Install certificate
      env:
        CERTIFICATE_P12: ${{ secrets.IOS_CERTIFICATE_P12 }}
        CERTIFICATE_PASSWORD: ${{ secrets.IOS_CERTIFICATE_PASSWORD }}
      run: |
        echo "$CERTIFICATE_P12" | base64 --decode > cert.p12
        security create-keychain -p actions temp.keychain
        security set-keychain-settings -lut 21600 temp.keychain
        security unlock-keychain -p actions temp.keychain
        security import cert.p12 -k temp.keychain -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k actions temp.keychain
        security list-keychains -d user -s temp.keychain
    
    - name: Install provisioning profile
      env:
        PROVISIONING_PROFILE: ${{ secrets.IOS_PROVISIONING_PROFILE }}
      run: |
        mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
        echo "$PROVISIONING_PROFILE" | base64 --decode > ~/Library/MobileDevice/Provisioning\ Profiles/profile.mobileprovision
    
    - name: Install XcodeGen
      run: brew install xcodegen
    
    - name: Generate project
      run: xcodegen generate
    
    - name: Build & Archive
      run: |
        xcodebuild archive \
          -project ReadIO.xcodeproj \
          -scheme ReadIO \
          -archivePath ReadIO.xcarchive \
          -destination 'generic/platform=iOS'
        
        xcodebuild -exportArchive \
          -archivePath ReadIO.xcarchive \
          -exportPath export \
          -exportOptionsPlist ExportOptions.plist
    
    - name: Upload IPA
      uses: actions/upload-artifact@v4
      with:
        name: ReadIO-iOS-IPA
        path: export/*.ipa
        retention-days: 30
```

#### 4. Create ExportOptions.plist
Create this file in your repo root:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

### Install on iPhone

Once you have the IPA:

**Option A: Xcode (Recommended)**
1. Download IPA from GitHub Actions artifacts
2. Connect iPhone to Mac
3. Open Xcode → Window → Devices and Simulators
4. Drag IPA onto your device

**Option B: TestFlight**
- Requires **paid** Apple Developer account ($99/year)
- Upload to App Store Connect → TestFlight
- Install via TestFlight app on iPhone

**Option C: Manual Install Tools**
- Use tools like `ios-deploy`, `ideviceinstaller`, or Configurator

## Option 3: Cloud Testing (No Mac Required)

If you don't have a Mac:
- **Appetize.io** - Run iOS simulators in browser
- **BrowserStack** - Test on real devices remotely  
- **MacinCloud** - Rent Mac access by the hour

## Current iOS Version Requirement

ReadIO requires **iOS 26.0+** (still in beta as of Feb 2026) due to Liquid Glass APIs.

To test on current devices:
1. Lower deployment target in `project.yml` to `16.0` or `17.0`
2. Wrap Liquid Glass code in `@available(iOS 26.0, *)` checks
3. Provide fallback UI for older iOS versions

---

**Questions?** Check https://github.com/PossiblyPengu/ReadIO/issues
