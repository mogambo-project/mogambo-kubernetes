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
    // ENVIRONMENT -> kubeconfig "Secret file" credential id
    ENV_CRED = "kubeconfig-${params.ENVIRONMENT}"
  }

  stages {
    stage('redeploy') {
      steps {
        withCredentials([file(credentialsId: env.ENV_CRED, variable: 'KUBECONFIG')]) {
          sh '''
            set -e
            echo "Environment : $ENVIRONMENT  (kubeconfig credential: $ENV_CRED)"
            echo "Context     : $(kubectl config current-context)"
            echo "Target      : deployment/$SERVICE  (namespace: $NAMESPACE, action: $ACTION)"
            kubectl -n "$NAMESPACE" get deploy "$SERVICE"

            if [ "$ACTION" = "scale-zero-then-up" ]; then
              REPS=$(kubectl -n "$NAMESPACE" get deploy "$SERVICE" -o jsonpath='{.spec.replicas}')
              [ -z "$REPS" ] && REPS=1
              echo "scaling $SERVICE to 0, then back to $REPS"
              kubectl -n "$NAMESPACE" scale deploy/"$SERVICE" --replicas=0
              sleep 3
              kubectl -n "$NAMESPACE" scale deploy/"$SERVICE" --replicas="$REPS"
            else
              kubectl -n "$NAMESPACE" rollout restart deploy/"$SERVICE"
            fi

            kubectl -n "$NAMESPACE" rollout status deploy/"$SERVICE" --timeout=180s
            echo "---- pods now ----"
            kubectl -n "$NAMESPACE" get pods -l app="$SERVICE" -o wide
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
