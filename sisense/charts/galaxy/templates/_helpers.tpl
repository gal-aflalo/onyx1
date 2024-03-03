{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "galaxy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "galaxy.fullname" -}}
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
{{- define "galaxy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create Sisense version from chart version
*/}}
{{- define "galaxy.sisense.version" -}}
{{- $sisenseVersion := split "." .Chart.Version -}}
{{- printf "%s.%s.%s" $sisenseVersion._0 $sisenseVersion._1 $sisenseVersion._2 | trimSuffix "." -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "galaxy.labels" -}}
release: {{ .Release.Name }}
app: {{ template "galaxy.name" . }}
chart: {{ template "galaxy.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
sisense-version: {{ include "galaxy.sisense.version" . }}
{{- if .Values.labels -}}
{{- range $key,$value := .Values.labels }}
{{ $key }}: {{ $value }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "galaxy.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "galaxy.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create template for galaxy container.
*/}}
{{- define "galaxy.container.command" -}}
command:
  - /bin/sh
  - -cx
  - |
    mkdir -p /opt/sisense/storage/emails;
    mkdir -p /opt/sisense/storage/backups;

    cp -fr /usr/src/app/dist/features/emails/templates /tmp/;
    rm -fr /usr/src/app/dist/features/emails/templates;
    cd /usr/src/app/dist/features/emails && ln -s /opt/sisense/storage/emails /usr/src/app/dist/features/emails/templates;
    if [ -f /opt/sisense/storage/emails/styles.less ]; then
      cd /opt/sisense/storage/emails/ && tar -zcf /opt/sisense/storage/backups/emails_backup-last_version-`date +'%y-%m-%d-%H-%M'`.tar.gz .;
      cd /opt/sisense/storage/backups && ls -t *emails* | tail -n +2 | xargs rm -rf;
      if [[ $(md5sum /opt/sisense/storage/emails/images/logo_black.png | awk '{print $1}') == "d957a0ae9d22b29426dd7879d1166a80" ]]; then
        cp -fr /tmp/templates/* /usr/src/app/dist/features/emails/templates/;
      fi
      if [[ ! -d /opt/sisense/storage/emails/test_email ]]; then
        cp -fr /tmp/templates/test_email /usr/src/app/dist/features/emails/templates/
      fi
    else
      cp -fr /tmp/templates/* /usr/src/app/dist/features/emails/templates/;
    fi
    cd /usr/src/app && npm start;
{{- end }}


{{/*
Name of formula-management app
*/}}
{{- define "formula.name" -}}
{{- default .Values.formula.image.name .Values.formulaNameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Formula Management Service labels
*/}}
{{- define "formula.serviceLabels" -}}
release: {{ .Release.Name }}
app: {{ template "formula.name" . }}
chart: {{ template "galaxy.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
sisense-version: {{ include "galaxy.sisense.version" . }}
{{- end -}}

{{/*
Helper function to determine CPU limit based on conditions
*/}}
{{- define "galaxy.limits.cpu" -}}
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
{{- define "galaxy.limits.memory" -}}
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
{{- define "galaxy.replicas" -}}
{{- if .Values.replicaCount -}}
{{- .Values.replicaCount -}}
{{- else if and (.Values.global.clusterMode).enabled .Values.global.highAvailability -}}
{{- 2 -}}
{{- else -}}
{{- 1 -}}
{{- end -}}
{{- end -}}
