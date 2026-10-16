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
├── Makefile                  # builds the gradeable deliverables (make submit ...)
├── SUBMISSIONS               # which attempt is the accepted pick per exercise
├── .env.example              # template for your personal settings (student id)
├── .env                      # YOUR student id — gitignored, copy from .env.example
├── .gitignore                # ignores tfstate, .terraform, zips, .env, dist/, .DS_Store
├── dist/                     # build output (zip + report PDF) — gitignored
│
├── Exercise_1/
│   ├── Exercise_01_...pdf     # shared instructions (lives at the exercise root)
│   ├── anna/                  # Anna's attempt
│   │   ├── report.md          #   report source -> rendered to the report PDF
│   │   └── src/               #   == the source zip payload (README.md + code)
│   ├── matti/
│   │   ├── report.md
│   │   └── src/
│   └── paul/
│       ├── report.md
│       └── src/
├── Exercise_2/
│   └── ...
└── Final_Project/             # created when the project starts
```

**Rule:** each person works **only inside their own `Exercise_N/<name>/` folder**.
Because everyone touches different paths, branch → `main` merges never conflict.

**Per-person folder:** put all gradeable source in `src/` (it becomes the submission
zip, flat) and write the report in `report.md` (it becomes the report PDF).

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

## Setup (needed to build submissions)

Building deliverables needs **`make`**, **`zip`**, and **Node.js** (for the
Markdown → PDF step, via `npx md-to-pdf`).

- **macOS:** `make` and `zip` ship with the Xcode CLT (`xcode-select --install`).
  Node: `brew install node`.
- **Windows:** `cmd`/PowerShell have no `make`/`zip`. Use **WSL** or **Git Bash**,
  which provide `make`, `zip`, and `bash`. Install Node inside that environment
  (or install [Node for Windows](https://nodejs.org) and run `make` from Git Bash).

Node sanity check: `node -v && npx -v`. The first `md-to-pdf` run downloads a
headless Chromium (one-time, a few hundred MB), then renders the PDF.

Then set your student id once:

```bash
cp .env.example .env        # then edit .env: MATRIKEL=cs123456 (your real id)
```

`.env` is **gitignored** — each teammate keeps their own. `SUBMISSIONS` (shared)
decides *which* solution ships; `.env` decides *whose id* the files are named with.

## Building the submission

The accepted pick per exercise is recorded in the tracked **`SUBMISSIONS`** file
(`<exercise-number> <tab> <owner>`). That file is the record of what we uploaded for
grading — commit it whenever a pick changes.

```bash
make record EX=1 WHO=matti   # mark matti as the accepted Exercise 1 solution (edits SUBMISSIONS)
make submit EX=1             # package the accepted pick (owner read from SUBMISSIONS)
make submit EX=1 WHO=paul    # override the owner for a one-off build
make all                     # package every accepted pick in SUBMISSIONS
make clean                   # remove dist/ (all built artifacts)
```

`make submit EX=1` produces, in `dist/` and named with your `.env` id:

```
dist/exc01_source_cs123456.zip   # contents of the owner's src/ (README.md + code), flat
dist/exc01_report_cs123456.pdf   # the owner's report.md rendered to PDF
```

Outputs are **build artifacts** — gitignored, created on demand, never committed.
The source zip skips `.terraform/`, `*.tfstate*`, `.DS_Store`, `.gitkeep`, and nested
`*.zip`. If an owner has no `report.md`, the report PDF is skipped (zip still builds).
After an exercise is finalized: `make record`, commit `SUBMISSIONS`, then `make submit`
(or `make all`) and upload both files from `dist/` to the course platform.

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

`.gitignore` excludes Terraform state (`*.tfstate`, `.terraform/`), `*.zip`,
`.DS_Store`, your personal **`.env`**, the **`dist/`** build dir, and rendered
report PDFs. Don't commit those. (The shared instruction PDFs stay tracked.)
