{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "sisense-utils.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "sisense-utils.fullname" -}}
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
{{- define "sisense-utils.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create Sisense version from chart version
*/}}
{{- define "sisense-utils.sisense.version" -}}
{{- $sisenseVersion := split "." .Chart.Version -}}
{{- printf "%s.%s.%s" $sisenseVersion._0 $sisenseVersion._1 $sisenseVersion._2 | trimSuffix "." -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "sisense-utils.labels" -}}
release: {{ .Release.Name }}
app: {{ template "sisense-utils.name" . }}
chart: {{ template "sisense-utils.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
sisense-version: {{ include "sisense-utils.sisense.version" . }}
{{- if .Values.labels -}}
{{- range $key,$value := .Values.labels }}
{{ $key }}: {{ $value }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Add custom labels
*/}}
{{- define "sisense-utils.customlabels" -}}
{{- if .Values.labels -}}
{{- range $key,$value := .Values.labels }}
{{ $key }}: {{ $value }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "sisense-utils.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "sisense-utils.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Use the sisense owner id*/}}
{{- define "sisense-utils.ownerid" -}}
{{- $isupdate := include "sisense.update" . -}}
{{- if eq $isupdate "true" -}}
{{- $cm := printf "cm-logmon-%s-env" .Release.Namespace -}}
{{ (lookup "v1" "ConfigMap" .Release.Namespace $cm ).data.sisense_ownerid -}}
{{- else -}}
devops@sisense.com
{{- end -}}
{{- end -}}

{{/*If regular cloudLoadBalancer, then check if there's already pre-existing SYSTEM_ALIAS (example: when updating sisense)
(If there is, then use it, thus will skip rollout restart for all of the pods in validator's function "update_system_alias"*/}}
{{- define "sisense-utils.define.system.alias" -}}
  {{- if and (not (.Values.global.ssl).enabled | default false) (ne (.Values.global.gatewayPort | default "30845" | quote) "80") (not (.Values.global.albController).enabled | default false) -}}
    {{- $configmap := (lookup "v1" "ConfigMap" .Release.Namespace "global-configuration") }}
    {{- if $configmap -}}
      {{- $alias := get $configmap.data "SYSTEM_ALIAS" }}
      {{- printf "%s" $alias -}}
    {{- else -}}
      {{- printf "%s" (.Values.global.external_kube_apiserver_address | default "") -}}
    {{- end -}}
  {{- else -}}
    {{- printf "%s" (.Values.global.external_kube_apiserver_address | default "") -}}
  {{- end -}}
{{- end -}}
