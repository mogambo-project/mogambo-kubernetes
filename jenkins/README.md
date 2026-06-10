# Jenkins SOPS jobs — how they were built, how to run them, and how to set them up on a new machine

This directory contains **everything needed to recreate the two SOPS Jenkins jobs on any
machine**, version-controlled in git:

| Path | What it is |
|------|-----------|
| `pipelines/sops-encrypt.Jenkinsfile` | The encrypt pipeline (the actual logic). |
| `pipelines/sops-decrypt.Jenkinsfile` | The decrypt pipeline (the actual logic). |
| `jobs/sops-encrypt.job.xml` | Jenkins job definition → "Pipeline from SCM", points at the encrypt Jenkinsfile. |
| `jobs/sops-decrypt.job.xml` | Jenkins job definition → "Pipeline from SCM", points at the decrypt Jenkinsfile. |
| `install-jobs.sh` | Recreates both jobs in a running Jenkins container from the files above. |
| `README.md` | This document. |

> **TL;DR for a new developer:** install `sops`+`age` locally, get/generate an age key, start
> the stack (`docker compose up -d --build` in `bootcamp/setup/`), add two Jenkins credentials
> (`github-token`, `sops-age-key`), then run `./jenkins/install-jobs.sh`. Full steps in
> [§5 New-developer setup](#5-new-developer-setup).

---

## 1. What problem these jobs solve

Kubernetes Secrets are base64, **not encrypted**, so we can't commit them to git as-is.
[SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age) let us commit
**encrypted** secret files safely. The rules live in [`../.sops.yaml`](../.sops.yaml): any file
matching `.*secret.*\.yaml` is encrypted to the age recipient (public key) listed there.

- **Encrypting** a file needs only the **public** recipient (from `.sops.yaml`).
- **Decrypting** a file needs the matching **private** age key.

The two jobs wrap those two operations so they can be run from Jenkins instead of by hand.

---

## 2. What was added to Jenkins to make this work

Three things. All are version-controlled (nothing lives only "on the machine") **except secrets**,
which by design are provided per-environment as Jenkins credentials.

### 2a. Tools baked into the Jenkins image — [`../../bootcamp/setup/Dockerfile`](../../bootcamp/setup/Dockerfile)
The base `jenkins/jenkins:lts` image has neither `sops` nor `age`. We added them so they survive
image rebuilds (not just container restarts):

```dockerfile
ARG SOPS_VERSION=3.9.4
RUN apt-get update \
  && apt-get install -y age \
  && ARCH="$(dpkg --print-architecture)" \
  && curl -fsSL -o /usr/local/bin/sops \
       "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${ARCH}" \
  && chmod +x /usr/local/bin/sops \
  && rm -rf /var/lib/apt/lists/*
```
`git` and the needed pipeline plugins (`workflow-*`, `git`, `credentials`, `credentials-binding`,
`plain-credentials`) ship with the image already.

### 2b. Two credentials (the only per-machine secrets)
Created in **Manage Jenkins → Credentials → System → Global**:

| ID | Kind | Used by | Purpose |
|----|------|---------|---------|
| `github-token` | Secret text | encrypt job | open the PR (push branch + call GitHub API) |
| `sops-age-key` | Secret file | decrypt job | the age **private** key for decryption |

The pipelines reference these **by ID only** — the secret values never appear in code or git.
See [§6 Secrets: the right way](#6-secrets-the-right-way).

### 2c. The two jobs themselves
Defined by the `jobs/*.job.xml` here and installed with `install-jobs.sh`. They are
**"Pipeline from SCM"**: the job is just a pointer that says *"check out this repo and run this
Jenkinsfile"*, so the real logic is the versioned `Jenkinsfile`, not buried inside Jenkins.

> **Earlier (non-portable) version:** the jobs were first created by writing inline
> `config.xml` straight into the Jenkins data volume, and the age key was a **host bind-mount** of
> `~/.config/sops/age`. That worked on the original PC but couldn't be reproduced elsewhere. The
> files in this directory are the corrected, portable replacement — see [§4](#4-why-the-first-version-wasnt-portable-and-the-jenkins-sops-jobs-folder).

---

## 3. The two jobs — how each is built and how to use it

### `sops-encrypt`
**Stages:** `Prepare plaintext → Encrypt with SOPS → Archive artifact → Open PR (optional)`

1. **Prepare plaintext** — either writes your pasted text to `secrets/<FILENAME>` (`MODE=PASTE_TEXT`)
   or targets an existing repo file (`MODE=EXISTING_REPO_FILE`). Validates the name matches the
   `.sops.yaml` rule.
2. **Encrypt with SOPS** — `sops --encrypt --in-place`. Uses only the public recipient, so **no key
   is required to encrypt**.
3. **Archive artifact** — the encrypted file is attached to the build (download it from the build page).
4. **Open PR** *(only if `OPEN_PR=true`)* — commits to a branch `sops-encrypt-<build#>`, pushes with
   `github-token`, and opens a PR via the GitHub API.

**Parameters:** `MODE`, `INPUT_TEXT`, `FILENAME`, `TARGET_PATH`, `BASE_BRANCH`, `OPEN_PR`.

**Use it:** Build with Parameters → pick `MODE`, fill the text/path → optionally tick `OPEN_PR` →
Build. Grab the encrypted file from **Artifacts**, or review the auto-opened PR.

### `sops-decrypt`
**Stages:** `Decrypt → Archive artifact`

1. **Decrypt** — binds `sops-age-key` to `SOPS_AGE_KEY_FILE`, then:
   - `SCOPE=SINGLE`: decrypts `FILE_PATH`.
   - `SCOPE=ALL`: decrypts every `*secret*.yaml` that contains a `sops:` block (plaintext files are skipped).
2. **Archive artifact** — decrypted output is attached as `decrypted-*`.

**Parameters:** `SCOPE`, `FILE_PATH`.

> ⚠️ The decrypt artifacts are **plaintext secrets**. Delete the build when done, or lock down who can
> run/read this job. For applying to the cluster, prefer piping instead of downloading:
> `sops -d secrets/x-secret.yaml | kubectl apply -f -`.

> **First build note:** because parameters are declared inside the Jenkinsfile, the *first* build of a
> newly-created job runs with defaults and just registers the parameters. From the second build you get
> the **Build with Parameters** screen.

---

## 4. Why the first version wasn't portable, and the `~/jenkins-sops-jobs` folder

**Question you asked:** *"If another developer runs this project on another machine, will the jobs be
there?"* — **No, not with the original approach.** Here's the mental model:

- Jenkins stores its jobs/config/credentials in `$JENKINS_HOME` (`/var/jenkins_home`), which is the
  Docker **named volume** `setup_jenkins-data`. That volume lives **only on your machine**. A teammate
  who clones the repo and runs `docker compose up` gets a **fresh, empty** Jenkins — image tooling
  (sops/age/plugins, because that's in the Dockerfile) but **no jobs and no credentials**.
- `~/jenkins-sops-jobs/` (outside the repo, in your home dir) was just a **scratch/backup folder** I
  used to stage the `config.xml` files before copying them into that volume with `docker cp`. Jenkins
  does **not** read from it — it's not connected to Jenkins at all. It isn't in git, so teammates never
  see it. **It is safe to delete** once the definitions live in this `jenkins/` directory.

**The fix (this directory):** the job definitions and pipeline code now live **in the repo**. Any
machine reproduces the jobs by running `./jenkins/install-jobs.sh` (or via JCasC — see below). That's
the best practice: *infrastructure/config as code, in version control.*

**Even better (optional next step): JCasC.** The
[Configuration-as-Code plugin](https://github.com/jenkinsci/configuration-as-code-plugin) lets a
`jenkins.yaml` in the repo declare jobs **and** credentials (sourced from env vars) automatically on
startup — no `install-jobs.sh` step. It's the gold standard for "clone and go"; `install-jobs.sh` is the
simpler stepping stone we use today.

---

## 5. New-developer setup

Everything a teammate needs to make these changes work on their machine.

### 5.1 Install the CLI tools locally (Ubuntu/WSL)
```bash
sudo apt-get update && sudo apt-get install -y age
SOPS_VER=3.9.4
sudo curl -fsSL -o /usr/local/bin/sops \
  "https://github.com/getsops/sops/releases/download/v${SOPS_VER}/sops-v${SOPS_VER}.linux.$(dpkg --print-architecture)"
sudo chmod +x /usr/local/bin/sops
sops --version && age --version
```

### 5.2 Get an age key
The age **private** key is what decrypts secrets. Two options:

- **Reuse the project key** (simplest for a small team): obtain `keys.txt` from whoever holds it via a
  secure channel and save it to `~/.config/sops/age/keys.txt` (`chmod 600`).
- **Use your own key** (better — no private-key sharing): generate one, then add *your* public key as an
  additional recipient in [`../.sops.yaml`](../.sops.yaml) and re-encrypt the files so you can decrypt too:
  ```bash
  mkdir -p ~/.config/sops/age
  age-keygen -o ~/.config/sops/age/keys.txt      # prints your PUBLIC key (age1...)
  # add that public key under creation_rules[].age in .sops.yaml (comma-separated),
  # then: sops updatekeys secrets/*-secret.yaml
  ```

### 5.3 Start the stack
```bash
cd bootcamp/setup
docker compose up -d --build       # builds the Jenkins image (sops/age baked in) and starts everything
# Jenkins → http://localhost:8080
```

### 5.4 Add the two Jenkins credentials
**Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

1. **`github-token`** — Kind **Secret text**. Create a GitHub **fine-grained PAT** on
   `mogambo-project/mogambo-kubernetes` with **Contents: Read & write** + **Pull requests: Read & write**,
   paste it, set ID = `github-token`.
2. **`sops-age-key`** — Kind **Secret file**. Upload your `~/.config/sops/age/keys.txt`, set ID =
   `sops-age-key`.

### 5.5 Create the jobs
```bash
cd <repo root>            # mogambo-kubernetes/
./jenkins/install-jobs.sh
```
Open http://localhost:8080 → run `sops-encrypt` / `sops-decrypt`.

---

## 6. Secrets: the right way

### The age private key — where should it live?
**Rule: it's a secret. Never commit it, never bake it into an image.** Provide it per-environment.

| Place | Use it for | Notes |
|-------|-----------|-------|
| **Jenkins "Secret file" credential** (`sops-age-key`) | the decrypt **job** | ✅ what we use now. Portable, encrypted at rest in `$JENKINS_HOME`, swappable in one click. |
| **Host bind-mount of `~/.config/sops/age`** | quick local hacking | ⚠️ what we did first. Tied to one person's home dir → **not portable**. Avoid for shared setups. |
| **A Kubernetes Secret + a SOPS operator** (e.g. sops-secrets-operator, or Flux/Argo with SOPS) | letting the **cluster** decrypt committed secrets (GitOps) | Advanced. The key is stored once as a k8s Secret; the cluster decrypts `SopsSecret` resources itself. This is the most "hands-off" model if you outgrow decrypt-in-CI. |

So: **you did *not* need to mount it from your PC.** The portable answer is the `sops-age-key`
credential (already wired into the decrypt Jenkinsfile). The bind-mount in
[`../../bootcamp/setup/docker-compose.yml`](../../bootcamp/setup/docker-compose.yml) can be removed once
you've added the credential — see [§7 Migration](#7-migrating-the-running-instance-to-this-setup).

**Don't run "decrypt everything" on a schedule or expose plaintext** — decryption should be on-demand
(a job run) or in-cluster via an operator, never sitting around as files.

### The GitHub token — where should it live?
**Already best practice:** it's a Jenkins **Secret text** credential (`github-token`), referenced in the
pipeline **by ID only**. That answers your questions directly:
- *"Do I add it inside the code / as a secret?"* — **Not in code.** As a Jenkins credential (a secret).
- *"How does the project use it?"* — `withCredentials([string(credentialsId: 'github-token', ...)])`
  injects it only for the steps that need it, and Jenkins **masks** it in logs.
- *"How does it remember it / where do I replace it?"* — it's stored (encrypted) in `$JENKINS_HOME`.
  Replace it in **one place**: Manage Jenkins → Credentials → `github-token` → Update. No code change.
- **Rotate** it whenever it leaks or on a schedule; use a **fine-grained PAT** scoped to just this repo
  with the minimum permissions (Contents + Pull requests, read/write).

> For full "clone and go" reproducibility, JCasC can create `github-token` from an environment variable
> (e.g. `GITHUB_TOKEN`) at startup, so a teammate just exports the var instead of clicking the UI.

---

## 7. Migrating the running instance to this setup

The currently-running Jenkins still uses the *old* inline jobs + the age key **bind-mount**. To move it
onto this version-controlled, credential-based setup:

1. Commit & push this `jenkins/` directory to `master` (the SCM jobs read the Jenkinsfiles from there).
2. Add the **`sops-age-key`** Secret-file credential (§5.4) — needed because the new decrypt pipeline
   uses the credential, not the mount.
3. `./jenkins/install-jobs.sh` — replaces the inline jobs with the SCM-backed ones.
4. Remove the bind-mount line from `bootcamp/setup/docker-compose.yml`:
   ```yaml
   - /home/andrio/.config/sops/age:/var/sops-age:ro   # delete this
   ```
   then `docker compose up -d` to recreate Jenkins without it.
5. Verify: run `sops-decrypt` (SINGLE on `secrets/carts-db-secret.yaml`) and `sops-encrypt`.
