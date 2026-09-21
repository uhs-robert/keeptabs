PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
SHAREDIR := $(PREFIX)/share/keeptabs
BINS := keeptabs-hook keeptabs-pick keeptabs-waybar

.PHONY: install link uninstall check

install:
	install -Dm755 -t $(BINDIR) $(addprefix bin/,$(BINS))
	install -Dm644 -t $(SHAREDIR) share/keeptabs/lib.sh

# Symlink instead of copy, so edits in this checkout apply immediately.
link:
	mkdir -p $(BINDIR) $(dir $(SHAREDIR))
	$(foreach b,$(BINS),ln -sfn $(CURDIR)/bin/$(b) $(BINDIR)/$(b);)
	ln -sfn $(CURDIR)/share/keeptabs $(SHAREDIR)

uninstall:
	rm -f $(addprefix $(BINDIR)/,$(BINS))
	rm -rf $(SHAREDIR)

check:
	shellcheck bin/* share/keeptabs/lib.sh
	shfmt -i 2 -d bin share
