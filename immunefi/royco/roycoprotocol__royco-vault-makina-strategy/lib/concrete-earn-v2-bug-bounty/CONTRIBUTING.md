# Contributing Guidelines

## Branch Management

### 1. Main Branch Policy
- **`main` is protected.**  
  Only **audited and approved code** may be merged into `main`.  
- Code merges into `main` **only after** the corresponding **audit report is completed** and all **remediation actions** have been implemented.
- **Exceptions:**  
  The only pull requests allowed directly into `main` without audit are:
  - Deployment scripts  
  - Documentation updates  
  - Auxiliary tools or configurations that **do not enter production code paths**

---

### 2. Branching Strategy
- All development work occurs in **feature branches**.  
  Example:
  ```bash
  git checkout -b feature/CONC-XXX-new-feature
  ```
- There is **no `develop` branch**.  
  Each audit corresponds to exactly **one feature branch**, ensuring clear traceability between audit cycles and code changes.

---

### 3. Release Management
- Every **production deployment** must result in a **release tag**.  
  Example:
  ```bash
  git tag -a v1.3.0 -m "Release v1.3.0 - post-audit changes"
  git push origin v1.3.0
  ```
- Release notes should reference:
  - The associated audit report  
  - Any remediation or relevant issues resolved

---

### Summary
- `main` → only audited code  
- `feature/*` → all new work  
- One audit = one feature branch  
- Each production deployment = one release tag
