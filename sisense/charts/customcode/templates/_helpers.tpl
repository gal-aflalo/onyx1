{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "customcode.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "customcode.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "customcode.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create Sisense version from chart version
*/}}
{{- define "customcode.sisense.version" -}}
{{- $sisenseVersion := split "." .Chart.Version -}}
{{- printf "%s.%s.%s" $sisenseVersion._0 $sisenseVersion._1 $sisenseVersion._2 | trimSuffix "." -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "customcode.labels" -}}
release: {{ .Release.Name }}
app: {{ template "customcode.name" . }}
chart: {{ template "customcode.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
sisense-version: {{ include "customcode.sisense.version" . }}
{{- if .Values.labels -}}
{{- range $key,$value := .Values.labels }}
{{ $key }}: {{ $value }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "customcode.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "customcode.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "customcode.calicoNetworkpolicy" -}}
{{- $apiVersion := "" }}
{{- if .Capabilities.APIVersions.Has "crd.projectcalico.org/v1" }}
  {{- $apiVersion = "crd.projectcalico.org/v1" }}
{{- else if .Capabilities.APIVersions.Has "crd.projectcalico.org/v3" }}
  {{- $apiVersion = "crd.projectcalico.org/v3" }}
{{- end }}
{{- if and $apiVersion (not (lookup $apiVersion "GlobalNetworkPolicy" "" "diag-network-policy")) }}
apiVersion: {{ $apiVersion }}
kind: GlobalNetworkPolicy
metadata:
  name:  diag-network-policy
  namespace: {{ .Release.Namespace }}
metadata:
  name:  diag-network-policy
spec:
  selector: app == "customcode"
  types:
  - Ingress
  - Egress
  ingress: []
  egress:
  - action: Allow
    destination:
      selector: app == 'api-gateway'
  - action: Allow
    destination:
      selector: app.kubernetes.io/instance == 'aws-load-balancer-controller'
  - action: Allow
    destination:
      selector: k8s-app == 'kube-dns'
  - action: Deny
    destination:
      nets:
        - 169.254.169.254/32
  - action: Deny
    destination:
      selector: release == 'sisense'
  - action: Deny
    destination:
      selector: release == 'sisense-prom-operator'
  - action: Deny
    destination:
      selector: app.kubernetes.io/instance == 'sisense'
  - action: Deny
    destination:
      selector: has(k8s-app)
  - action: Allow
    destination:
      notSelector: release == 'sisense'
  - action: Allow
    destination:
      notSelector: app.kubernetes.io/instance == 'sisense'
{{- end }}
{{- end }}

{{/*
Helper function to determine CPU limit based on conditions
*/}}
{{- define "customcode.limits.cpu" -}}
{{- if (.Values.resources.limits).cpu -}}
{{- .Values.resources.limits.cpu -}}
{{- else if eq "small" (.Values.global.deploymentSize | lower | default "small") -}}
{{- .Values.resources_small.limits.cpu -}}
{{- else if eq "large" (.Values.global.deploymentSize | lower) -}}
{{- .Values.resources_large.limits.cpu -}}
{{- else -}}
{{- .Values.resources_small.limits.cpu -}}
{{- end -}}
{{- end -}}


{{/*
Helper function to determine Memory limit based on conditions
*/}}
{{- define "customcode.limits.memory" -}}
{{- if (.Values.resources.limits).memory -}}
{{- .Values.resources.limits.memory -}}
{{- else if eq "small" (.Values.global.deploymentSize | lower | default "small") -}}
{{- .Values.resources_small.limits.memory -}}
{{- else if eq "large" (.Values.global.deploymentSize | lower) -}}
{{- .Values.resources_large.limits.memory -}}
{{- else -}}
{{- .Values.resources_small.limits.memory -}}
{{- end -}}
{{- end -}}
