# Sound Recorder: a Mac app and the sysaudio-record CLI, sharing one ScreenCaptureKit capture engine.
SHELL      := /bin/bash
OUT         = out
APP         = $(OUT)/Sound Recorder.app
EXE         = SoundRecorder
APPDIR     ?= $(HOME)/Applications/Sound Recorder.app
BINDIR     ?= $(HOME)/.local/bin
# Stable self-signed identity (made by que-huong-studio/packaging/make-signing-cert.sh): macOS keeps the
# Screen & System Audio Recording and Microphone permissions across rebuilds only if the signature stays the same.
IDENTITY   ?= Que Huong Studio Signing
SWIFTC      = swiftc -O -target arm64-apple-macos15.0
ENGINE      = Sources/Engine/CaptureEngine.swift
FRAMEWORKS  = -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia -framework CoreGraphics -framework Accelerate

.PHONY: all app cli install install-cli check-strings run clean

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

# Both languages must define the same keys.
check-strings:
	@for f in Resources/*.lproj/*.strings Resources/Info.plist; do plutil -lint -s "$$f" || exit 1; done
	@diff <(plutil -convert json -o - Resources/en.lproj/Localizable.strings | tr ',' '\n' | grep -o '"[^"]*":' | sort) \
	      <(plutil -convert json -o - Resources/vi.lproj/Localizable.strings | tr ',' '\n' | grep -o '"[^"]*":' | sort) \
	  || { echo "en and vi Localizable.strings keys differ" >&2; exit 1; }

app: check-strings $(OUT)/AppIcon.icns
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	$(SWIFTC) -parse-as-library $(ENGINE) Sources/App/*.swift -o "$(APP)/Contents/MacOS/$(EXE)" $(FRAMEWORKS) -framework SwiftUI -framework AppKit
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp -R Resources/en.lproj Resources/vi.lproj $(OUT)/AppIcon.icns "$(APP)/Contents/Resources/"
	@if security find-identity -p codesigning | grep -q "\"$(IDENTITY)\""; then id="$(IDENTITY)"; \
	  else echo "warning: signing identity \"$(IDENTITY)\" not found; ad-hoc signing (permissions reset on every build)" >&2; id=-; fi; \
	  codesign --force --timestamp=none --sign "$$id" "$(APP)" && echo "signed with: $$id"
	codesign --verify --strict "$(APP)"

# install: the app into ~/Applications (quits a running copy first, so a recording gets finalized)
install: app
	-osascript -e 'tell application id "com.macb.sound-recorder" to quit' >/dev/null 2>&1
	rm -rf "$(APPDIR)"
	ditto "$(APP)" "$(APPDIR)"
	@echo "installed $(APPDIR)"

install-cli: cli
	install -d "$(BINDIR)"
	install -m 755 $(OUT)/sysaudio-record "$(BINDIR)/sysaudio-record"
	@echo "installed $(BINDIR)/sysaudio-record"

run: install
	open "$(APPDIR)"

clean:
	rm -rf $(OUT)
