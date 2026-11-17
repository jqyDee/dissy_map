# EX05 Report: [Exercise Title]

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  
**Group Name:** `MAP`

---

## Task 1 - [Fault Tolerance & Coordination]

### Infrastructure

To setup our five nodes and the zookeeper server we will use 6 multipass ubuntu virtual machines. This decision was made because they can easily be setup via a shell script once multipass is installed locally.

Taking a look at `multipass_up.sh`:

```
#!/usr/bin/env bash
set -e

# Launch VM $1 with RAM $2, unless it already exists
# multipass info succeeds when vm already exists -> multipass launch isnt executed
launch() {
  multipass info "$1" >/dev/null 2>&1 || multipass launch 24.04 --name "$1" --memory "$2"
}

# ZooKeeper VM
launch zk 1G
until multipass exec zk -- true 2>/dev/null; do sleep 2; done
multipass exec zk -- sudo apt-get update
multipass exec zk -- sudo apt-get install -y zookeeperd

# 5 application nodes
for i in 1 2 3 4 5; do
  launch node$i 512M
done

multipass list
```

---

## Task 2 - [Title]

### Code Sample
```python
# Insert your source code snippet here
def main():
    print("Distributed Systems Exercise")

if __name__ == "__main__":
    main()
```

### Figure Sample

Insert images or screenshots of your results, architectures, or execution outputs.

## Discussion Questions

>Question 1: What are your observations regarding...?

Your answer here...

>Question 2: Explain the trade-offs between...

Your answer here...

<!--
Delete this guide section before submitting — it must not appear in the report PDF.

How to generate the PDF (this repo):
- This is the template. Copy it to your folder as the report source:
    cp report.template.md Exercise_<N>/<you>/report.md
  then fill in the sections above.
- Build it with the Makefile (renders report.md -> dist/exc0N_report_<STUDENT_ID>.pdf):
    make submit EX=<N>
  (set your UIBK username once in .env; see the repo README "Setup"). Uses `npx md-to-pdf`.

Alternatives if you prefer:
- VS Code: install the "Markdown PDF" extension, right-click -> Markdown PDF: Export (pdf).
- Browser: open the Markdown preview, Cmd/Ctrl+P -> Save as PDF.
-->
