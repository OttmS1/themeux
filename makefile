INSTALL_DIR := $(HOME)/.local/bin
INSTALL_NAME := themeux

install:
	sed 's|__THEMEUX_DIR__|$(CURDIR)|g' main.sh > $(INSTALL_DIR)/$(INSTALL_NAME)
	chmod 755 $(INSTALL_DIR)/$(INSTALL_NAME)

uninstall:
	rm -f $(INSTALL_DIR)/$(INSTALL_NAME)

.PHONY: install uninstall
