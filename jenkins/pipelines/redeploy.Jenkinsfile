// Redeploy a microservice's pods in a chosen environment.
//
// MAINTAINABILITY / multi-env design:
//   The target cluster is selected by the ENVIRONMENT parameter, which maps to a
//   Jenkins "Secret file" credential named  kubeconfig-<environment>.
//   To onboard a new environment (e.g. staging, prod in the cloud):
//     1. Add a "Secret file" credential 'kubeconfig-staging' (that cluster's kubeconfig).
//     2. Add 'staging' to the ENVIRONMENT choices below.
//   No other change needed — the pipeline auto-selects the credential by name.
//
//   Today only 'dev' is wired (the local kind cluster, credential 'kubeconfig-dev').
pipeline {
  agent any
  options { timestamps() }

  parameters {
    choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'prod'],
           description: 'Target environment. Only "dev" (local kind) is configured today.')
    choice(name: 'SERVICE', choices: ['catalogue', 'carts', 'frontend', 'catalogue-db', 'carts-db'],
           description: 'Deployment to redeploy.')
    string(name: 'NAMESPACE', defaultValue: 'mogambo', trim: true,
           description: 'Kubernetes namespace.')
    choice(name: 'ACTION', choices: ['rollout-restart', 'scale-zero-then-up'],
           description: 'rollout-restart = graceful recreate (re-pulls :latest when imagePullPolicy=Always). scale-zero-then-up = hard restart.')
  }

  environment {
    // Map params into env vars so the pipeline works on the FIRST build too: on a fresh
    // Pipeline-from-SCM job, $PARAM env vars aren't populated on build #1, but params.X
    // defaults are — so we derive the env vars from params.X here.
    DEPLOY_ENV = "${params.ENVIRONMENT}"
    ENV_CRED   = "kubeconfig-${params.ENVIRONMENT}"   // ENVIRONMENT -> kubeconfig-<env> credential id
    SVC        = "${params.SERVICE}"
    NS         = "${params.NAMESPACE}"
    ACT        = "${params.ACTION}"
  }

  stages {
    stage('redeploy') {
      steps {
        withCredentials([file(credentialsId: env.ENV_CRED, variable: 'KUBECONFIG')]) {
          sh '''
            set -e
            echo "Environment : $DEPLOY_ENV  (kubeconfig credential: $ENV_CRED)"
            echo "Context     : $(kubectl config current-context)"
            echo "Target      : deployment/$SVC  (namespace: $NS, action: $ACT)"
            kubectl -n "$NS" get deploy "$SVC"

            if [ "$ACT" = "scale-zero-then-up" ]; then
              REPS=$(kubectl -n "$NS" get deploy "$SVC" -o jsonpath='{.spec.replicas}')
              [ -z "$REPS" ] && REPS=1
              echo "scaling $SVC to 0, then back to $REPS"
              kubectl -n "$NS" scale deploy/"$SVC" --replicas=0
              sleep 3
              kubectl -n "$NS" scale deploy/"$SVC" --replicas="$REPS"
            else
              kubectl -n "$NS" rollout restart deploy/"$SVC"
            fi

            kubectl -n "$NS" rollout status deploy/"$SVC" --timeout=180s
            echo "---- pods now ----"
            kubectl -n "$NS" get pods -l app="$SVC" -o wide
          '''
        }
      }
    }
  }

  post {
    failure {
      echo "Redeploy failed. If ENVIRONMENT != dev, check that the 'kubeconfig-${params.ENVIRONMENT}' credential exists."
    }
  }
}
