APP_NAME = UsageMeter
BUNDLE_ID = com.henry.usagemeter
BUILD_DIR = build
APP = $(BUILD_DIR)/$(APP_NAME).app
BINARY = .build/release/$(APP_NAME)
ICON_SRC = icon/AppIcon.png
ICONSET = $(BUILD_DIR)/AppIcon.iconset
ICNS = $(BUILD_DIR)/AppIcon.icns

.PHONY: build icns bundle install run dmg clean

build:
	swift build -c release

# Build a multi-resolution .icns from the 1024x1024 master.
icns: $(ICON_SRC)
	rm -rf $(ICONSET)
	mkdir -p $(ICONSET)
	sips -z 16 16     $(ICON_SRC) --out $(ICONSET)/icon_16x16.png      >/dev/null
	sips -z 32 32     $(ICON_SRC) --out $(ICONSET)/icon_16x16@2x.png   >/dev/null
	sips -z 32 32     $(ICON_SRC) --out $(ICONSET)/icon_32x32.png      >/dev/null
	sips -z 64 64     $(ICON_SRC) --out $(ICONSET)/icon_32x32@2x.png   >/dev/null
	sips -z 128 128   $(ICON_SRC) --out $(ICONSET)/icon_128x128.png    >/dev/null
	sips -z 256 256   $(ICON_SRC) --out $(ICONSET)/icon_128x128@2x.png >/dev/null
	sips -z 256 256   $(ICON_SRC) --out $(ICONSET)/icon_256x256.png    >/dev/null
	sips -z 512 512   $(ICON_SRC) --out $(ICONSET)/icon_256x256@2x.png >/dev/null
	sips -z 512 512   $(ICON_SRC) --out $(ICONSET)/icon_512x512.png    >/dev/null
	cp $(ICON_SRC)    $(ICONSET)/icon_512x512@2x.png
	iconutil -c icns $(ICONSET) -o $(ICNS)

bundle: build icns
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/$(APP_NAME)
	cp $(ICNS) $(APP)/Contents/Resources/AppIcon.icns
	printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'	<key>CFBundleExecutable</key><string>$(APP_NAME)</string>' \
		'	<key>CFBundleIconFile</key><string>AppIcon</string>' \
		'	<key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>' \
		'	<key>CFBundleName</key><string>$(APP_NAME)</string>' \
		'	<key>CFBundlePackageType</key><string>APPL</string>' \
		'	<key>CFBundleShortVersionString</key><string>1.0</string>' \
		'	<key>CFBundleVersion</key><string>1</string>' \
		'	<key>LSMinimumSystemVersion</key><string>13.0</string>' \
		'	<key>LSUIElement</key><true/>' \
		'</dict>' \
		'</plist>' \
		> $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

install: bundle
	pkill -x $(APP_NAME) 2>/dev/null || true
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/
	open /Applications/$(APP_NAME).app

run: bundle
	pkill -x $(APP_NAME) 2>/dev/null || true
	open $(APP)

# Build a drag-to-Applications disk image at build/UsageMeter.dmg.
dmg: bundle
	bash scripts/make_dmg.sh

clean:
	rm -rf .build $(BUILD_DIR)
