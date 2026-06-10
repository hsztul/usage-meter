APP_NAME = UsageMeter
BUNDLE_ID = com.henry.usagemeter
BUILD_DIR = build
APP = $(BUILD_DIR)/$(APP_NAME).app
BINARY = .build/release/$(APP_NAME)

.PHONY: build bundle install run clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BINARY) $(APP)/Contents/MacOS/$(APP_NAME)
	printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'	<key>CFBundleExecutable</key><string>$(APP_NAME)</string>' \
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

clean:
	rm -rf .build $(BUILD_DIR)
