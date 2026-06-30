APP = WiFiMonitor.app
BINARY = .build/debug/WiFiMonitor
ICONSET = .build/AppIcon.iconset
ICNS = .build/AppIcon.icns

.PHONY: build run clean

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

clean:
	rm -rf .build $(APP)
