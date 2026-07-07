APP = WiFiMonitor.app
BINARY = .build/debug/WiFiMonitor
RELEASE_BINARY = .build/release/WiFiMonitor
ICONSET = .build/AppIcon.iconset
ICNS = .build/AppIcon.icns

# Signing/notarization (see docs/signing.md):
#   SIGN_IDENTITY  e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE keychain profile from `xcrun notarytool store-credentials`
.PHONY: build run clean release-build sign dist

MASKED_PNG = .build/AppIcon-masked.png

$(MASKED_PNG): AppIcon.png scripts/squircle.swift
	mkdir -p .build
	swiftc scripts/squircle.swift -o .build/squircle
	.build/squircle AppIcon.png $(MASKED_PNG)

$(ICNS): $(MASKED_PNG)
	mkdir -p $(ICONSET)
	sips -z 16 16     $(MASKED_PNG) --out $(ICONSET)/icon_16x16.png
	sips -z 32 32     $(MASKED_PNG) --out $(ICONSET)/icon_16x16@2x.png
	sips -z 32 32     $(MASKED_PNG) --out $(ICONSET)/icon_32x32.png
	sips -z 64 64     $(MASKED_PNG) --out $(ICONSET)/icon_32x32@2x.png
	sips -z 128 128   $(MASKED_PNG) --out $(ICONSET)/icon_128x128.png
	sips -z 256 256   $(MASKED_PNG) --out $(ICONSET)/icon_128x128@2x.png
	sips -z 256 256   $(MASKED_PNG) --out $(ICONSET)/icon_256x256.png
	sips -z 512 512   $(MASKED_PNG) --out $(ICONSET)/icon_256x256@2x.png
	sips -z 512 512   $(MASKED_PNG) --out $(ICONSET)/icon_512x512.png
	sips -z 1024 1024 $(MASKED_PNG) --out $(ICONSET)/icon_512x512@2x.png
	iconutil -c icns $(ICONSET) -o $(ICNS)

build: $(ICNS)
	swift build
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	cp $(ICNS) $(APP)/Contents/Resources/

run: build
	touch $(APP)
	/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f $(APP)
	open $(APP)

# Release-configuration bundle (optimized binary, same assembly as `build`).
release-build: $(ICNS)
	swift build -c release
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Resources
	cp $(RELEASE_BINARY) $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	cp $(ICNS) $(APP)/Contents/Resources/

# Developer ID sign with hardened runtime + secure timestamp.
sign: release-build
	@test -n "$(SIGN_IDENTITY)" || { echo "Set SIGN_IDENTITY, e.g. 'Developer ID Application: Your Name (TEAMID)'"; exit 1; }
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" $(APP)
	codesign --verify --strict --verbose=2 $(APP)

# Notarize the signed bundle and staple the ticket, producing WiFiMonitor.zip.
dist: sign
	@test -n "$(NOTARY_PROFILE)" || { echo "Set NOTARY_PROFILE (see: xcrun notarytool store-credentials)"; exit 1; }
	ditto -c -k --keepParent $(APP) WiFiMonitor.zip
	xcrun notarytool submit WiFiMonitor.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(APP)
	ditto -c -k --keepParent $(APP) WiFiMonitor.zip
	@echo "Notarized and stapled: WiFiMonitor.zip"

clean:
	rm -rf .build $(APP) WiFiMonitor.zip
