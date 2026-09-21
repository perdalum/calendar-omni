.DEFAULT_GOAL := all
# Xcode operations share DerivedData; avoid concurrent builds from make -j.
.NOTPARALLEL:

PREFIX ?= $(HOME)
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=
COMPLETIONDIR ?= $(HOME)/.zsh/completion
BUILD_DIR ?= build
CONFIGURATION ?= Release
XCODEBUILD ?= xcodebuild
PYTHON ?= python3

BINARY = $(BUILD_DIR)/Build/Products/$(CONFIGURATION)/CalendarOmni
XCODE_ARGS = -project CalendarOmni.xcodeproj -scheme CalendarOmni \
	-derivedDataPath "$(BUILD_DIR)" -clonedSourcePackagesDirPath "$(BUILD_DIR)/SourcePackages"

.PHONY: all build debug test check install uninstall completions clean help

all: build

build:
	$(XCODEBUILD) $(XCODE_ARGS) -configuration "$(CONFIGURATION)" build

debug:
	$(MAKE) build CONFIGURATION=Debug

# The unit tests and CLI checks do not access Calendar or write events.
test: check
	$(XCODEBUILD) $(XCODE_ARGS) -configuration Debug -destination 'platform=macOS' test

check: build
	$(PYTHON) scripts/check_cli.py "$(BINARY)"

install: build
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 755 "$(BINARY)" "$(DESTDIR)$(BINDIR)/CalendarOmni"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/CalendarOmni"

# Separate from install: no shell configuration or completion changes by default.
completions: build
	./scripts/install-zsh-completion "$(BINARY)" "$(DESTDIR)$(COMPLETIONDIR)"

# Let Xcode remove build products while retaining downloaded package sources.
clean:
	$(XCODEBUILD) $(XCODE_ARGS) -configuration Release clean
	$(XCODEBUILD) $(XCODE_ARGS) -configuration Debug clean

help:
	@echo 'make / make build    Build Release (override CONFIGURATION if needed)'
	@echo 'make debug           Build Debug'
	@echo 'make test            Run Swift tests and CLI checks'
	@echo 'make check           Run CLI checks only, after building'
	@echo 'make install         Build and install to ~/bin by default'
	@echo 'make uninstall       Remove the executable from the install destination'
	@echo 'make completions     Build and install zsh completion definitions'
	@echo 'make clean           Clean Debug/Release products, retain package sources'
	@echo 'Overrides: PREFIX, BINDIR, DESTDIR, COMPLETIONDIR, BUILD_DIR, CONFIGURATION'
	@echo 'Example: make install PREFIX="$$HOME/.local"'
