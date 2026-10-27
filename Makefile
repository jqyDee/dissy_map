# Final submission packaging.
#
# Builds the two gradeable deliverables the course expects, per exercise:
#   dist/exc0X_source_<STUDENT_ID>.zip   <- README.md + source (the chosen solution's src/)
#   dist/exc0X_report_<STUDENT_ID>.pdf   <- that solution's report.md, rendered to PDF
#                                           (**Student Name:**/**Student ID:** lines
#                                           replaced by STUDENT_NAME/STUDENT_ID from .env)
#
# One submission per team: SUBMISSIONS records WHICH solution (owner) we picked.
# But each member packages it under THEIR OWN id, read from .env (STUDENT_ID).
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

# Personal settings (STUDENT_ID=...). Silent if missing so `record`/`clean` still work.
-include .env

# Files inside src/ that must never end up in the submission zip.
ZIP_EXCLUDES := '.terraform/*' '*/.terraform/*' '*.terraform.lock.hcl' '*.tfstate*' '.DS_Store' '*/.DS_Store' '.gitkeep' '*.zip' '*/PIL/*' '*/pillow*' '*/lambda_build/*' '*/__pycache__/*' '*.log'

.PHONY: submit all record clean check-student-id check-node

submit: check-student-id check-node
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
	zipout="$(CURDIR)/$(DIST)/$${tag}_source_$(STUDENT_ID).zip"; \
	rm -f "$$zipout"; \
	( cd "$$dir/src" && zip -r -q "$$zipout" . -x $(ZIP_EXCLUDES) ); \
	echo "built $(DIST)/$${tag}_source_$(STUDENT_ID).zip  (from $$dir/src, owner=$$who)"; \
	if [ -f "$$dir/report.md" ]; then \
		pdfout="$(DIST)/$${tag}_report_$(STUDENT_ID).pdf"; \
		tmpmd="$$dir/.report.build.md"; \
		STUDENT_NAME="$(STUDENT_NAME)" STUDENT_ID="$(STUDENT_ID)" awk ' \
			/^\*\*Student Name:\*\*/ { print "**Student Name:** " ENVIRON["STUDENT_NAME"] "  "; next } \
			/^\*\*Student ID:\*\*/   { print "**Student ID:** `" ENVIRON["STUDENT_ID"] "`  "; next } \
			{ print }' "$$dir/report.md" > "$$tmpmd"; \
		npx --yes md-to-pdf "$$tmpmd" >/dev/null || { rm -f "$$tmpmd"; exit 1; }; \
		rm -f "$$tmpmd"; \
		mv "$$dir/.report.build.pdf" "$$pdfout"; \
		echo "built $$pdfout  (from $$dir/report.md, as $(STUDENT_NAME) / $(STUDENT_ID))"; \
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

check-student-id:
	@test -n "$(STUDENT_ID)" || { echo "STUDENT_ID is empty. Copy .env.example to .env and set your UIBK username (csXXXXXX)."; exit 1; }
	@test "$(STUDENT_ID)" != "csXXXXXX" || { echo "STUDENT_ID is still the placeholder (csXXXXXX). Edit .env with your real UIBK username."; exit 1; }
	@test -n "$(STUDENT_NAME)" || { echo "STUDENT_NAME is empty. Set it in .env (used on the report PDF)."; exit 1; }

check-node:
	@command -v npx >/dev/null || { echo "npx not found. Install Node.js (needed for md-to-pdf). See README setup."; exit 1; }
