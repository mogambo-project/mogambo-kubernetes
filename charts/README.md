# Helm charts

Empty on purpose — fill it when you're ready for the layer above raw manifests.

## Why use Helm

After you've written a few raw manifests by hand (the [`manifests/`](../manifests/) reference), you'll notice patterns:

- The same labels copied to every resource
- Image tags hardcoded instead of injected per environment
- 6 nearly-identical Deployment files for 6 microservices

Helm fixes this with **templating + values**. A *chart* packages a set of templated manifests + a `values.yaml` defaults file + a `Chart.yaml` metadata file.

## Scaffold your first chart

```bash
cd ~/kubernetes-bootcamp-claude/charts
helm create example-chart
ls example-chart/
```

Helm gives you a fully working starter chart. Open `templates/deployment.yaml` and notice the `{{ .Values.image.repository }}` syntax — those are pulled from `values.yaml`.

## What each file in a chart is for

| File | Purpose |
|---|---|
| `Chart.yaml` | Chart metadata: name, version, appVersion (the version of the *app*, not the chart) |
| `values.yaml` | Default values; users override with `--set` or `-f my-values.yaml` |
| `templates/` | Templated YAML files (manifests with Go template directives) |
| `templates/_helpers.tpl` | Reusable template snippets (label sets, full names) |
| `templates/NOTES.txt` | Printed after `helm install` — put usage hints here |
| `.helmignore` | Like `.gitignore` but for `helm package` |
| `charts/` | Subcharts (dependencies) |

## Working with a chart

```bash
helm lint example-chart                                       # validate syntax
helm template example-chart                                   # render templates locally without installing
helm install foo example-chart -n playground --create-namespace
helm upgrade foo example-chart -n playground --set replicaCount=3
helm rollback foo 1 -n playground                             # revert to revision 1
helm uninstall foo -n playground

helm list -A                                                  # all installed releases
helm get values foo -n playground                             # what values are in effect
helm get manifest foo -n playground                           # the rendered manifests
```

## Suggested first chart project

Convert one of your bootcamp Ansible roles (e.g. `catalogue`) into a Helm chart. You already understand the service from the Ansible side — translating it teaches you Helm without inventing new domain logic.

A reasonable shape:

```
charts/catalogue/
├── Chart.yaml
├── values.yaml          # image, replicaCount, service.port, ingress.host, dbUrl
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    └── configmap.yaml
```

Then once you have *one* chart, do `frontend`, `carts`, and `mongo` — each as separate charts, then optionally compose them under one umbrella chart with `dependencies:` in Chart.yaml.
