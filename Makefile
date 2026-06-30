APP = WiFiMonitor.app
BINARY = .build/debug/WiFiMonitor
ICONSET = .build/AppIcon.iconset
ICNS = .build/AppIcon.icns

.PHONY: build run clean

$(ICNS): AppIcon.png
	mkdir -p $(ICONSET)
	sips -z 16 16     AppIcon.png --out $(ICONSET)/icon_16x16.png
	sips -z 32 32     AppIcon.png --out $(ICONSET)/icon_16x16@2x.png
	sips -z 32 32     AppIcon.png --out $(ICONSET)/icon_32x32.png
	sips -z 64 64     AppIcon.png --out $(ICONSET)/icon_32x32@2x.png
	sips -z 128 128   AppIcon.png --out $(ICONSET)/icon_128x128.png
	sips -z 256 256   AppIcon.png --out $(ICONSET)/icon_128x128@2x.png
	sips -z 256 256   AppIcon.png --out $(ICONSET)/icon_256x256.png
	sips -z 512 512   AppIcon.png --out $(ICONSET)/icon_256x256@2x.png
	sips -z 512 512   AppIcon.png --out $(ICONSET)/icon_512x512.png
	sips -z 1024 1024 AppIcon.png --out $(ICONSET)/icon_512x512@2x.png
	iconutil -c icns $(ICONSET) -o $(ICNS)

build: $(ICNS)
	swift build
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	cp $(ICNS) $(APP)/Contents/Resources/

run: build
	open $(APP)

clean:
	rm -rf .build $(APP)
