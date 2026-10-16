# UE Distributed Systems — Team Repository

Shared repository for the *UE Distributed Systems* seminar: **5 exercises** followed by a
**final group project**. Team: **Anna**, **Matti**, **Paul**.

Everyone solves every exercise on their own branch. We merge the best result of each
exercise into `main`, so `main` is always the single, combined submission.

---

## Repository layout

```
.
├── README.md                 # this file
├── Makefile                  # builds the gradeable submission zip (make submit ...)
├── .gitignore                # ignores tfstate, .terraform, zips, .DS_Store
│
├── Exercise_1/
│   ├── Exercise_01_...pdf     # shared instructions (lives at the exercise root)
│   ├── anna/                  # Anna's attempt
│   ├── matti/                 # Matti's attempt
│   └── paul/                  # Paul's attempt
├── Exercise_2/
│   └── ...
└── Final_Project/             # created when the project starts
```

**Rule:** each person works **only inside their own `Exercise_N/<name>/` folder**.
Because everyone touches different paths, branch → `main` merges never conflict.

---

## Branches

| Branch  | Purpose                                                        |
|---------|----------------------------------------------------------------|
| `main`  | The combined submission. Always working. Protected — PRs only. |
| `anna`  | Anna's long-lived personal branch.                             |
| `matti` | Matti's long-lived personal branch.                            |
| `paul`  | Paul's long-lived personal branch.                             |

Personal branches live the whole term — do **not** delete them between exercises.

---

## Workflow per exercise

1. **Sync** your branch with the latest `main`:
   ```bash
   git checkout matti          # your branch
   git merge main --no-edit    # pull in the newest combined state
   ```
2. **Work** inside your folder only, e.g. `Exercise_2/matti/`. Commit as you go:
   ```bash
   git add Exercise_2/matti
   git commit -m "feat(matti): Exercise 2 load balancer"
   git push origin matti
   ```
3. **Open a Pull Request** `your-branch → main` when your attempt is ready.
4. **One teammate reviews** and approves.
5. **Merge** (squash) into `main`.
6. **Everyone re-syncs** their branch (`git merge main --no-edit`).

### Finalizing an exercise (choosing the combined submission)

Before the deadline the team compares all three `Exercise_N/<name>/` folders and picks
(or combines) the best one. The owner of the chosen solution opens the PR that lands it in
`main`. The other attempts stay in their folders as record — only the chosen one is zipped
for grading.

---

## Pull Request rules

- **Never commit directly to `main`** (except the one-time scaffold below).
- One PR = one exercise's work. Keep them scoped.
- Needs **1 approval** from a teammate before merge.
- Prefer **squash merge** to keep `main` history clean.
- Title convention: `Exercise N: <short summary> (<name>)`.

---

## Commit message convention

Conventional-commit style, scope = your name:

```
feat(matti): Exercise 1 terraform VPC + compute
fix(anna):   Exercise 2 fix healthcheck path
chore(paul): move Exercise 1 solution into paul/
```

---

## Building the submission

The accepted pick per exercise is recorded in the tracked **`SUBMISSIONS`** file
(`<exercise-number> <tab> <owner>`). That file is the record of what we uploaded for
grading — commit it whenever a pick changes.

```bash
make record EX=1 WHO=matti   # mark matti as the accepted Exercise 1 solution (edits SUBMISSIONS)
make all                     # build a zip for every accepted pick in SUBMISSIONS
make submit EX=1 WHO=matti   # build just one zip -> Exercise_1/Exercise_1_submission.zip
make clean                   # remove all built submission zips
```

Zips are **build artifacts** — gitignored, created on demand, never committed.
Packaging skips `.terraform/`, `*.tfstate*`, `.DS_Store`, and nested `*.zip`.
After an exercise is finalized: `make record`, commit `SUBMISSIONS`, then `make submit`
(or `make all`) and upload the zip to the course platform.

---

## One-time setup (already done once by the first person)

```bash
# On main: add README, Makefile, and the per-person folders.
git checkout main
git add README.md Makefile Exercise_*/*/.gitkeep
git commit -m "chore: team workflow + per-person exercise folders"
git push origin main

# Each person pulls the structure into their branch:
git checkout <name> && git merge main --no-edit && git push origin <name>
```

## Ignored files

`.gitignore` already excludes Terraform state (`*.tfstate`, `.terraform/`),
`*.zip`, and `.DS_Store`. Don't commit those.
