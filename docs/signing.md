# Signing & notarizing WiFi Monitor

WiFi Monitor is distributed as a Developer ID–signed, notarized `.app` so it
runs on any Mac without Gatekeeper warnings, and so the Location Services and
Keychain grants persist across builds (both are keyed to the signing identity +
bundle ID `com.rcolburn.wifimonitor`).

## One-time: create a Developer ID Application certificate

No full Xcode required — use Keychain Access + the developer portal.

1. **Generate a CSR.** Keychain Access → menu **Certificate Assistant → Request
   a Certificate From a Certificate Authority**. Enter your email, leave "CA
   Email" blank, choose **Saved to disk**, and save `CertificateSigningRequest.certSigningRequest`.
2. **Create the cert.** At <https://developer.apple.com/account/resources/certificates>,
   click **+**, choose **Developer ID Application**, upload the CSR, and
   download the resulting `.cer`.
3. **Install it.** Double-click the `.cer` to add it to the login keychain. If
   prompted, also install the "Developer ID Certification Authority"
   intermediate from <https://www.apple.com/certificateauthority/>.
4. **Verify:**
   ```
   security find-identity -v -p codesigning
   ```
   You should see `Developer ID Application: Your Name (TEAMID)`.

Your **Team ID** is the 10-character code in that identity, also shown under
Membership at <https://developer.apple.com/account>.

## One-time: notarization credentials

1. Create an **app-specific password** at <https://appleid.apple.com> → Sign-In
   & Security → App-Specific Passwords.
2. Store a reusable notarytool profile in the keychain:
   ```
   xcrun notarytool store-credentials "wifimonitor-notary" \
     --apple-id "you@example.com" \
     --team-id "TEAMID" \
     --password "abcd-efgh-ijkl-mnop"
   ```

## Local signed + notarized build

```
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="wifimonitor-notary"
make dist
```

This builds the release binary, assembles the bundle with the checked-in
`Info.plist`, signs with hardened runtime + secure timestamp, notarizes, staples
the ticket, and produces `WiFiMonitor.zip`. Verify the result:

```
codesign --verify --strict --verbose=2 WiFiMonitor.app
spctl -a -vvv -t install WiFiMonitor.app   # should say "accepted / Notarized Developer ID"
xcrun stapler validate WiFiMonitor.app
```

## CI (tagged releases)

`.github/workflows/release.yml` signs and notarizes automatically on a `v*` tag.
It needs these repository secrets:

| Secret | What |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | Developer ID cert+key exported as `.p12`, base64-encoded |
| `DEVELOPER_ID_CERT_PASSWORD` | Password set when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | Any string; used for the throwaway CI keychain |
| `NOTARY_APPLE_ID` | Your Apple ID email |
| `NOTARY_TEAM_ID` | Your 10-char Team ID |
| `NOTARY_PASSWORD` | The app-specific password |

Export the `.p12` from Keychain Access (select **both** the Developer ID
Application cert and its private key → right-click → Export), then:

```
base64 -i Certificates.p12 | pbcopy   # paste into DEVELOPER_ID_CERT_P12_BASE64
```
