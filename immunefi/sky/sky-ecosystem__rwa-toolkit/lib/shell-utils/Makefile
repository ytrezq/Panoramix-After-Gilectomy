NAME=ces-shell-utils
VERSION=0.3.0

DIRS=bin
SRC_DIRS=`find $(DIRS) -type d 2>/dev/null`
SRC_FILES=`find $(DIRS) -type f 2>/dev/null`
SRC_DOC_FILES=*.md LICENSE
SRC_SCRIPT_DIR=scripts
SRC_SCRIPT_FILES=`find $(SRC_SCRIPT_DIR) -type f 2>/dev/null`

BUILD_DIR=.build
BIN_DIR=$(BUILD_DIR)/bin
BIN_FILES=`find $(BIN_DIR) -type f 2>/dev/null`
MAN_DIRS=$(BUILD_DIR)/share/man/man1
MAN_FILES=`find $(MAN_DIRS) -type f 2>/dev/null`
DOC_DIR=$(BUILD_DIR)/share/doc/$(PKG_NAME)
DOC_FILES=`find $(DOC_DIR) -type f 2>/dev/null`

PKG_DIR=pkg
PKG_NAME=$(NAME)-$(VERSION)
PKG=$(PKG_DIR)/$(PKG_NAME).tar.gz
SIG=$(PKG_DIR)/$(PKG_NAME).tar.gz.asc

PREFIX?=$(HOME)/.local
INSTALL_BIN_DIR=$(PREFIX)/bin
INSTALL_DOC_DIR=$(PREFIX)/share/doc/$(PKG_NAME)
INSTALL_MAN_DIR=$(PREFIX)/share/man

all: clean build pkg sign

clean:
	rm -f $(PKG) $(SIG)
	rm -rf $(BUILD_DIR)/*

build-dir:
	mkdir -p $(BUILD_DIR);

build-src:
	for file in $(SRC_FILES); do \
		mkdir -p $(BUILD_DIR)/$$(dirname $$file); \
		sed -r 's/\$$\{VERSION:-0.0.0\}/$(VERSION)/g' $$file > $(BUILD_DIR)/$$file; \
		chmod a+x $(BUILD_DIR)/$$file; \
	done

build-man:
	for dir in $(MAN_DIRS); do \
		mkdir -p $$dir; \
		for file in $(SRC_FILES); do \
			VERSION=$(VERSION) help2man --no-info --no-discard-stderr $$file | nroff -man > $$dir/$$(basename $$file).1; \
		done \
	done

build-doc:
	mkdir -p $(DOC_DIR)
	for file in $(SRC_DOC_FILES); do \
		cp $$file $(DOC_DIR); \
	done
	cp $(SRC_DOC_FILES) $(BUILD_DIR)

build-scripts:
	cp $(SRC_SCRIPT_FILES) $(BUILD_DIR)

build: build-dir clean build-src build-man build-doc build-scripts

pkg-dir:
	mkdir -p $(PKG_DIR)

$(PKG): pkg-dir
	cd $(BUILD_DIR) && tar -czf ../$(PKG) . && cd -

pkg: $(PKG)

$(SIG): $(PKG)
	gpg --sign --detach-sign --armor -o $(SIG) $(PKG)

sign: $(SIG)

test:

tag:
	git tag v$(VERSION)
	git push --tags

release:
	gh release create v$(VERSION) $(PKG) $(SIG)

install: build
	mkdir -p $(INSTALL_BIN_DIR)
	mkdir -p $(INSTALL_DOC_DIR)
	mkdir -p $(INSTALL_MAN_DIR)
	cp -r $(BIN_FILES) $(INSTALL_BIN_DIR)/
	cp -r $(DOC_FILES) $(INSTALL_DOC_DIR)/
	cp -r $(MAN_FILES) $(INSTALL_MAN_DIR)/

uninstall: build
	for file in $(BIN_FILES); do \
		find $(INSTALL_BIN_DIR) -name $$(basename $$file) -exec rm -rf -- '{}' +; \
	done
	for file in $(MAN_FILES); do \
		find $(INSTALL_MAN_DIR) -name $$(basename $$file) -exec rm -rf -- '{}' +; \
	done
	rm -rf $(INSTALL_DOC_DIR)

.PHONY: clean test release install uninstall all
