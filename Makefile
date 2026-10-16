# Final submission packaging.
# Zips one person's solution for a given exercise into a gradeable archive.
# Zips are gitignored build artifacts: created on demand, never committed.
#
# Usage:
#   make submit EX=1 WHO=matti    -> Exercise_1/Exercise_1_submission.zip
#   make clean                    -> remove all built submission zips

EX  ?=
WHO ?=

.PHONY: submit clean

submit:
	@test -n "$(EX)"  || { echo "set EX=<n>   e.g. make submit EX=1 WHO=matti"; exit 1; }
	@test -n "$(WHO)" || { echo "set WHO=<name> e.g. make submit EX=1 WHO=matti"; exit 1; }
	@test -d "Exercise_$(EX)/$(WHO)" || { echo "no such folder: Exercise_$(EX)/$(WHO)"; exit 1; }
	cd Exercise_$(EX) && zip -r "Exercise_$(EX)_submission.zip" "$(WHO)" -x '*/.terraform/*' '*.tfstate*' '*/.DS_Store'
	@echo "built Exercise_$(EX)/Exercise_$(EX)_submission.zip"

clean:
	rm -f Exercise_*/Exercise_*_submission.zip
