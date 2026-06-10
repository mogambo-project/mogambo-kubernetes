// SOPS encrypt pipeline (version-controlled — single source of truth).
// The job that runs this is defined in jenkins/jobs/sops-encrypt.job.xml as a
// "Pipeline script from SCM", so Jenkins checks this repo out into the workspace
// automatically (the workspace root IS the repo root — .sops.yaml and secrets/ are here).
//
// NOTE: parameters are declared here, so the FIRST build of a freshly-created job
// runs with defaults and only *registers* the parameters; from the 2nd build on you
// get "Build with Parameters".
pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }

  parameters {
    choice(name: 'MODE', choices: ['PASTE_TEXT', 'EXISTING_REPO_FILE'],
           description: 'PASTE_TEXT = encrypt the text you paste below. EXISTING_REPO_FILE = encrypt a file already in the repo.')
    text(name: 'INPUT_TEXT', defaultValue: '',
         description: '(PASTE_TEXT) The plaintext to encrypt — usually a Kubernetes Secret YAML.')
    string(name: 'FILENAME', defaultValue: 'new-secret.yaml', trim: true,
           description: '(PASTE_TEXT) File created under secrets/. MUST contain "secret" and end in .yaml (matches .sops.yaml).')
    string(name: 'TARGET_PATH', defaultValue: 'secrets/catalogue-db-secret.yaml', trim: true,
           description: '(EXISTING_REPO_FILE) Path in the repo to encrypt in place.')
    string(name: 'BASE_BRANCH', defaultValue: 'master', trim: true,
           description: 'Branch the PR targets (the job always checks out the branch configured in its SCM, normally master).')
    booleanParam(name: 'OPEN_PR', defaultValue: false,
                 description: 'If true, commit the encrypted file to a new branch and open a GitHub PR (needs the "github-token" credential).')
  }

  environment {
    GH_OWNER = 'mogambo-project'
    GH_REPO  = 'mogambo-kubernetes'
  }

  stages {
    stage('Prepare plaintext') {
      steps {
        script {
          if (params.MODE == 'PASTE_TEXT') {
            if (!params.INPUT_TEXT?.trim()) { error 'INPUT_TEXT is empty but MODE=PASTE_TEXT.' }
            if (!(params.FILENAME ==~ /.*secret.*\.yaml/)) {
              error "FILENAME '${params.FILENAME}' must contain 'secret' and end with .yaml (see .sops.yaml path_regex)."
            }
            writeFile file: "secrets/${params.FILENAME}", text: params.INPUT_TEXT
            env.TARGET = "secrets/${params.FILENAME}"
          } else {
            env.TARGET = params.TARGET_PATH
          }
        }
        sh '''
          echo "Target file: $TARGET"
          test -f "$TARGET" || { echo "ERROR: $TARGET does not exist in the repo"; exit 1; }
          if grep -q "^sops:" "$TARGET"; then
            echo "WARNING: $TARGET already looks SOPS-encrypted; sops will refuse to double-encrypt."
          fi
        '''
      }
    }

    stage('Encrypt with SOPS') {
      steps {
        // Encryption only needs the age RECIPIENT from .sops.yaml — no private key required.
        sh '''
          sops --version
          sops --encrypt --in-place "$TARGET"
          echo "---- encrypted file (first lines) ----"
          head -n 15 "$TARGET"
        '''
      }
    }

    stage('Archive artifact') {
      steps {
        sh 'mkdir -p out && cp "$TARGET" "out/$(basename "$TARGET")"'
        archiveArtifacts artifacts: 'out/*', fingerprint: true
        echo 'Encrypted file is downloadable under this build’s Artifacts.'
      }
    }

    stage('Open PR') {
      when { expression { return params.OPEN_PR } }
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
          sh '''
set -e
BRANCH="sops-encrypt-${BUILD_NUMBER}"
git config user.email "jenkins@mogambo.local"
git config user.name  "Jenkins SOPS Bot"
git checkout -b "$BRANCH"
git add "$TARGET"
git commit -m "Encrypt $TARGET via SOPS (build #${BUILD_NUMBER})"
git push "https://x-access-token:${GH_TOKEN}@github.com/${GH_OWNER}/${GH_REPO}.git" "$BRANCH"
# Build the PR body with a heredoc (avoids shell word-splitting on the JSON).
cat > pr-body.json <<JSON
{"title":"SOPS encrypt ${TARGET}","head":"${BRANCH}","base":"${BASE_BRANCH}","body":"Automated SOPS encryption from Jenkins build #${BUILD_NUMBER}."}
JSON
curl -fsSL -X POST \
  -H "Authorization: token ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/pulls" \
  -d @pr-body.json
rm -f pr-body.json
'''
        }
      }
    }
  }

  post {
    failure { echo 'Encrypt job failed - check the stage logs above.' }
  }
}
