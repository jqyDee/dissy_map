# Final submission packaging.
# Zips the accepted solution for an exercise into a gradeable archive.
# Zips are gitignored build artifacts: created on demand, never committed.
#
# The accepted pick per exercise is recorded in ./SUBMISSIONS (tracked in git).
# That file is the record of what we uploaded for grading.
#
# Usage:
#   make record EX=1 WHO=matti    # mark matti as the accepted Exercise 1 solution
#   make submit EX=1 WHO=matti    # build one zip  -> Exercise_1/Exercise_1_submission.zip
#   make all                      # build a zip for every accepted pick in SUBMISSIONS
#   make clean                    # remove all built submission zips

EX  ?=
WHO ?=
SUBMISSIONS_FILE ?= SUBMISSIONS

.PHONY: submit all record clean

submit:
	@test -n "$(EX)"  || { echo "set EX=<n>    e.g. make submit EX=1 WHO=matti"; exit 1; }
	@test -n "$(WHO)" || { echo "set WHO=<name> e.g. make submit EX=1 WHO=matti"; exit 1; }
	@test -d "Exercise_$(EX)/$(WHO)" || { echo "no such folder: Exercise_$(EX)/$(WHO)"; exit 1; }
	cd Exercise_$(EX) && zip -r "Exercise_$(EX)_submission.zip" "$(WHO)" -x '*/.terraform/*' '*.tfstate*' '*/.DS_Store' '*.zip'
	@echo "built Exercise_$(EX)/Exercise_$(EX)_submission.zip"

# Build a zip for every accepted pick listed in SUBMISSIONS.
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
	rm -f Exercise_*/Exercise_*_submission.zip
