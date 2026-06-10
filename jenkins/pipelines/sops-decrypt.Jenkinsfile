// SOPS decrypt pipeline (version-controlled — single source of truth).
// Defined as "Pipeline script from SCM" in jenkins/jobs/sops-decrypt.job.xml, so the
// repo is checked out into the workspace automatically (workspace root == repo root).
//
// The age PRIVATE key is provided by the Jenkins "Secret file" credential `sops-age-key`
// (best practice — portable across machines). This replaces the old host bind-mount of
// ~/.config/sops/age, which only worked on the original developer's PC.
//
// WARNING: this job writes PLAINTEXT secrets to build artifacts. Delete builds when done,
// or restrict who can run/read this job.
pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }

  parameters {
    choice(name: 'SCOPE', choices: ['SINGLE', 'ALL'],
           description: 'SINGLE = decrypt FILE_PATH only. ALL = decrypt every SOPS-encrypted *secret*.yaml in the repo.')
    string(name: 'FILE_PATH', defaultValue: 'secrets/carts-db-secret.yaml', trim: true,
           description: '(SINGLE) Path in the repo to decrypt.')
  }

  stages {
    stage('Decrypt') {
      steps {
        // file() binding writes the secret to a temp file and points SOPS_AGE_KEY_FILE at it.
        withCredentials([file(credentialsId: 'sops-age-key', variable: 'SOPS_AGE_KEY_FILE')]) {
          sh 'mkdir -p out'
          script {
            if (params.SCOPE == 'SINGLE') {
              sh '''
                test -f "$FILE_PATH" || { echo "ERROR: $FILE_PATH not found in repo"; exit 1; }
                base="$(basename "$FILE_PATH")"
                sops -d "$FILE_PATH" > "out/decrypted-$base"
                echo "Decrypted $FILE_PATH -> out/decrypted-$base"
              '''
            } else {
              sh '''
                found=0
                for f in $(find . -type f -name "*secret*.yaml" | sort); do
                  if grep -q "^sops:" "$f"; then
                    safe="$(echo "$f" | sed "s|^\\./||; s|/|_|g")"
                    sops -d "$f" > "out/decrypted-$safe"
                    echo "decrypted: $f -> out/decrypted-$safe"
                    found=$((found+1))
                  else
                    echo "skipped (not SOPS-encrypted): $f"
                  fi
                done
                echo "Total decrypted: $found"
                [ "$found" -gt 0 ] || echo "NOTE: no encrypted secret files found."
              '''
            }
          }
        }
      }
    }

    stage('Archive artifact') {
      steps {
        archiveArtifacts artifacts: 'out/*', allowEmptyArchive: true, fingerprint: false
        echo 'WARNING: archived artifacts contain PLAINTEXT secrets. Delete this build when done.'
      }
    }
  }

  post {
    failure { echo 'Decrypt job failed - check the stage logs above.' }
  }
}
