# Sound Recorder: a Mac app and the sysaudio-record CLI, sharing one ScreenCaptureKit capture engine.
SHELL      := /bin/bash
VERSION    ?= $(shell cat VERSION)
OUT         = out
APP         = $(OUT)/Sound Recorder.app
EXE         = SoundRecorder
APPDIR     ?= $(HOME)/Applications/Sound Recorder.app
BINDIR     ?= $(HOME)/.local/bin
# Stable self-signed code-signing identity in the login keychain: macOS keeps the
# Screen & System Audio Recording and Microphone permissions across rebuilds and updates only if the signature stays the same.
IDENTITY   ?= Que Huong Studio Signing
SWIFTC      = swiftc -O -target arm64-apple-macos15.0
ENGINE      = Sources/Engine/CaptureEngine.swift
APP_SOURCES = $(shell find Sources/App -name '*.swift' | sort)
FRAMEWORKS  = -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia -framework CoreGraphics -framework Accelerate
# Sparkle (auto-update): the official release archive gives both the framework the app embeds and the
# sign_update / generate_keys tools used by `make release`.
SPARKLE     = 2.10.0
SPARKLE_SHA = c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
SPARKLE_DIR = packaging/sparkle-tools
SPARKLE_OK  = $(SPARKLE_DIR)/.sparkle-$(SPARKLE)
# release notes travel to packaging/release.sh in the environment (they may span lines)
export NOTES

.PHONY: all app cli install install-cli check-strings sparkle-tools release run clean

all: app cli

cli: $(OUT)/sysaudio-record

$(OUT)/sysaudio-record: $(ENGINE) Sources/CLI/main.swift
	@mkdir -p $(OUT)
	$(SWIFTC) $^ -o $@ $(FRAMEWORKS)

$(OUT)/AppIcon.icns: tools/MakeIcon.swift
	@mkdir -p $(OUT)
	$(SWIFTC) $< -o $(OUT)/make-icon
	rm -rf $(OUT)/AppIcon.iconset && $(OUT)/make-icon $(OUT)/AppIcon.iconset
	iconutil -c icns $(OUT)/AppIcon.iconset -o $@

sparkle-tools: $(SPARKLE_OK)

$(SPARKLE_OK):
	@mkdir -p $(OUT)
	curl -sSfL -o $(OUT)/Sparkle-$(SPARKLE).tar.xz https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE)/Sparkle-$(SPARKLE).tar.xz
	echo "$(SPARKLE_SHA)  $(OUT)/Sparkle-$(SPARKLE).tar.xz" | shasum -a 256 -c -
	rm -rf $(SPARKLE_DIR) && mkdir -p $(SPARKLE_DIR)
	tar -xJ -C $(SPARKLE_DIR) -f $(OUT)/Sparkle-$(SPARKLE).tar.xz
	rm -f $(OUT)/Sparkle-$(SPARKLE).tar.xz
	touch $@

# Both languages must define the same keys.
check-strings:
	@for f in Resources/*.lproj/*.strings Resources/Info.plist; do plutil -lint -s "$$f" || exit 1; done
	@diff <(plutil -convert json -o - Resources/en.lproj/Localizable.strings | tr ',' '\n' | grep -o '"[^"]*":' | sort) \
	      <(plutil -convert json -o - Resources/vi.lproj/Localizable.strings | tr ',' '\n' | grep -o '"[^"]*":' | sort) \
	  || { echo "en and vi Localizable.strings keys differ" >&2; exit 1; }

app: check-strings $(OUT)/AppIcon.icns sparkle-tools
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" "$(APP)/Contents/Frameworks"
	$(SWIFTC) -parse-as-library $(ENGINE) $(APP_SOURCES) -o "$(APP)/Contents/MacOS/$(EXE)" $(FRAMEWORKS) \
	  -framework SwiftUI -framework AppKit -F $(SPARKLE_DIR) -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleVersion -string "$(VERSION)" "$(APP)/Contents/Info.plist"
	cp -R Resources/en.lproj Resources/vi.lproj $(OUT)/AppIcon.icns "$(APP)/Contents/Resources/"
	ditto $(SPARKLE_DIR)/Sparkle.framework "$(APP)/Contents/Frameworks/Sparkle.framework"
	bash packaging/sign-app.sh "$(APP)" "$(IDENTITY)"

# install: the app into ~/Applications (quits a running copy first, so a recording gets finalized)
install: app
	-osascript -e 'tell application id "com.macb.sound-recorder" to quit' >/dev/null 2>&1
	rm -rf "$(APPDIR)"
	ditto "$(APP)" "$(APPDIR)"
	@echo "installed $(VERSION) at $(APPDIR)"

install-cli: cli
	install -d "$(BINDIR)"
	install -m 755 $(OUT)/sysaudio-record "$(BINDIR)/sysaudio-record"
	@echo "installed $(BINDIR)/sysaudio-record"

# release: bump VERSION and commit/push first; publishes a GitHub release that installed apps update to.
release: sparkle-tools
	bash packaging/release.sh "$(VERSION)"

run: install
	open "$(APPDIR)"

clean:
	rm -rf $(OUT)
