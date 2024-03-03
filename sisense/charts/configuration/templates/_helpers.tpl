{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "configuration.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "configuration.fullname" -}}
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
{{- define "configuration.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create Sisense version from chart version
*/}}
{{- define "configuration.sisense.version" -}}
{{- $sisenseVersion := split "." .Chart.Version -}}
{{- printf "%s.%s.%s" $sisenseVersion._0 $sisenseVersion._1 $sisenseVersion._2 | trimSuffix "." -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "configuration.labels" -}}
release: {{ .Release.Name }}
app: {{ template "configuration.name" . }}
configuration-service: "true"
chart: {{ template "configuration.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
sisense-version: {{ include "configuration.sisense.version" . }}
{{- if .Values.labels -}}
{{- range $key,$value := .Values.labels }}
{{ $key }}: {{ $value }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "configuration.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "configuration.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create template for configuration container.
*/}}
{{- define "configuration.container.command" -}}
command:
  - /bin/sh
  - -cx
  - |
    mkdir -p /opt/sisense/storage/translations;
    mkdir -p /opt/sisense/storage/backups;

    if [ -f "/opt/sisense/storage/translations/en-US/email-templates.js" ]; then
      cd /opt/sisense/storage/translations/ && tar -zcf /opt/sisense/storage/backups/translations_backup-last_version-`date +'%y-%m-%d-%H-%M'`.tar.gz .;
      cd /opt/sisense/storage/backups && ls -t *translations* | tail -n +2 | xargs rm -rf;
    fi;

    rsync --ignore-existing -av /usr/src/app/translations/ /opt/sisense/storage/translations/;
    rm -rf /usr/src/app/translations;
    ln -sf /opt/sisense/storage/translations /usr/src/app/;
    cd /usr/src/app && yarn start;
{{- end }}

{{/*
Helper function to determine CPU limit based on conditions
*/}}
{{- define "configuration.limits.cpu" -}}
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
{{- define "configuration.limits.memory" -}}
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

{{/*
Helper function to determine replicas based on conditions
*/}}
{{- define "configuration.replicas" -}}
{{- if .Values.replicaCount -}}
{{- .Values.replicaCount -}}
{{- else if and (.Values.global.clusterMode).enabled .Values.global.highAvailability -}}
{{- 2 -}}
{{- else -}}
{{- 1 -}}
{{- end -}}
{{- end -}}
