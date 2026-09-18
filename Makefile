# Makefile — thin wrappers over bin/. See README.md.
#
#   make render NAME=ep001
#   make dry-run NAME=ep001
#   make check
#   make smoke

NAME    ?= ep001
INPUTS  ?= inputs
OUTPUTS ?= outputs
OUT     ?= $(OUTPUTS)/$(NAME)/master.mp4
MASTER  ?= $(OUT)
RUN_DIR ?= $(OUTPUTS)/$(NAME)

.PHONY: render dry-run check smoke clean help

help:
	@echo "make render NAME=ep001   render one master from $(INPUTS)/"
	@echo "make dry-run NAME=ep001  print the planned pipeline, run nothing"
	@echo "make check               scripts/check (shellcheck + schema)"
	@echo "make smoke               tiny end-to-end fixture, < 90 s"
	@echo "make clean               remove $(OUTPUTS)/* run directories"

render:
	bin/render-master.sh "$(NAME)" "$(MASTER)" "$(INPUTS)" "$(OUTPUTS)"

dry-run:
	bin/render-master.sh --dry-run "$(NAME)" "$(MASTER)" "$(INPUTS)" "$(OUTPUTS)"

check:
	scripts/check

smoke:
	scripts/smoke

clean:
	rm -rf "$(RUN_DIR)"
