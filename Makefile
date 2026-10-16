# Final submission packaging.
#
# Builds the two gradeable deliverables the course expects, per exercise:
#   dist/exc0X_source_<MATRIKEL>.zip   <- README.md + source (the chosen solution's src/)
#   dist/exc0X_report_<MATRIKEL>.pdf   <- that solution's report.md, rendered to PDF
#
# One submission per team: SUBMISSIONS records WHICH solution (owner) we picked.
# But each member packages it under THEIR OWN id, read from .env (MATRIKEL).
# So .env is personal/gitignored; SUBMISSIONS is shared/tracked.
#
# Layout assumed per person:
#   Exercise_N/<who>/
#     report.md          # report source -> rendered to the report PDF
#     src/               # == the source zip payload (README.md + code), zipped flat
#
# md -> pdf uses Node (portable across macOS/Windows): `npx --yes md-to-pdf`.
# make + zip are needed too; on Windows run from WSL or Git Bash. See README setup.
#
# Usage:
#   make submit EX=1              # package the accepted Exercise 1 pick (owner from SUBMISSIONS)
#   make submit EX=1 WHO=matti    # override the owner for a one-off build
#   make all                      # package every accepted pick in SUBMISSIONS
#   make record EX=1 WHO=matti    # mark matti as the accepted Exercise 1 solution
#   make clean                    # remove dist/ (all built artifacts)

EX  ?=
WHO ?=
SUBMISSIONS_FILE ?= SUBMISSIONS
DIST ?= dist

# Personal settings (MATRIKEL=...). Silent if missing so `record`/`clean` still work.
-include .env

# Files inside src/ that must never end up in the submission zip.
ZIP_EXCLUDES := '.terraform/*' '*/.terraform/*' '*.terraform.lock.hcl' '*.tfstate*' '.DS_Store' '*/.DS_Store' '.gitkeep' '*.zip'

.PHONY: submit all record clean check-matrikel check-node

submit: check-matrikel check-node
	@test -n "$(EX)" || { echo "set EX=<n>    e.g. make submit EX=1"; exit 1; }
	@set -e; \
	ex="$(EX)"; who="$(WHO)"; \
	if [ -z "$$who" ]; then \
		test -f "$(SUBMISSIONS_FILE)" || { echo "no $(SUBMISSIONS_FILE); pass WHO=<name> or run make record"; exit 1; }; \
		who=$$(grep -vE '^[[:space:]]*(#|$$)' "$(SUBMISSIONS_FILE)" | awk -v e="$$ex" '$$1==e{print $$2; exit}'); \
		test -n "$$who" || { echo "Exercise $$ex not in $(SUBMISSIONS_FILE); pass WHO=<name> or run make record EX=$$ex WHO=<name>"; exit 1; }; \
	fi; \
	dir="Exercise_$$ex/$$who"; \
	test -d "$$dir/src" || { echo "missing source dir: $$dir/src"; exit 1; }; \
	tag=$$(printf 'exc%02d' "$$ex"); \
	mkdir -p "$(DIST)"; \
	zipout="$(CURDIR)/$(DIST)/$${tag}_source_$(MATRIKEL).zip"; \
	rm -f "$$zipout"; \
	( cd "$$dir/src" && zip -r -q "$$zipout" . -x $(ZIP_EXCLUDES) ); \
	echo "built $(DIST)/$${tag}_source_$(MATRIKEL).zip  (from $$dir/src, owner=$$who)"; \
	if [ -f "$$dir/report.md" ]; then \
		pdfout="$(DIST)/$${tag}_report_$(MATRIKEL).pdf"; \
		npx --yes md-to-pdf "$$dir/report.md" >/dev/null; \
		mv "$$dir/report.md".pdf "$$pdfout" 2>/dev/null || mv "$${dir%/}/report.pdf" "$$pdfout"; \
		echo "built $$pdfout  (from $$dir/report.md)"; \
	else \
		echo "note: no $$dir/report.md -> skipped report PDF (zip only)"; \
	fi

# Package every accepted pick listed in SUBMISSIONS.
all:
	@test -f "$(SUBMISSIONS_FILE)" || { echo "nothing recorded yet ($(SUBMISSIONS_FILE) missing)"; exit 1; }
	@grep -vE '^[[:space:]]*(#|$$)' "$(SUBMISSIONS_FILE)" | while read -r ex who rest; do \
		[ -n "$$ex" ] || continue; \
		$(MAKE) --no-print-directory submit EX=$$ex WHO=$$who; \
	done

# Record (or overwrite) the accepted pick for an exercise in SUBMISSIONS.
record:
	@test -n "$(EX)"  || { echo "set EX=<n>    e.g. make record EX=1 WHO=matti"; exit 1; }
	@test -n "$(WHO)" || { echo "set WHO=<name> e.g. make record EX=1 WHO=matti"; exit 1; }
	@test -d "Exercise_$(EX)/$(WHO)" || { echo "no such folder: Exercise_$(EX)/$(WHO)"; exit 1; }
	@touch "$(SUBMISSIONS_FILE)"
	@grep -vE "^[[:space:]]*$(EX)[[:space:]]" "$(SUBMISSIONS_FILE)" > "$(SUBMISSIONS_FILE).tmp" 2>/dev/null || true
	@printf '%s\t%s\n' "$(EX)" "$(WHO)" >> "$(SUBMISSIONS_FILE).tmp"
	@mv "$(SUBMISSIONS_FILE).tmp" "$(SUBMISSIONS_FILE)"
	@echo "recorded Exercise $(EX) -> $(WHO) in $(SUBMISSIONS_FILE); commit it."

clean:
	rm -rf "$(DIST)"
	@echo "removed $(DIST)/"

# --- guards -------------------------------------------------------------

check-matrikel:
	@test -n "$(MATRIKEL)" || { echo "MATRIKEL is empty. Copy .env.example to .env and set your student id."; exit 1; }
	@test "$(MATRIKEL)" != "csXXXXXX" || { echo "MATRIKEL is still the placeholder (csXXXXXX). Edit .env with your real id."; exit 1; }

check-node:
	@command -v npx >/dev/null || { echo "npx not found. Install Node.js (needed for md-to-pdf). See README setup."; exit 1; }
