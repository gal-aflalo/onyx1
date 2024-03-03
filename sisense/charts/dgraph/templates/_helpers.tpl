{{/*
Expand the name of the chart.
*/}}
{{- define "dgraph.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "dgraph.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "dgraph.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dgraph.labels" -}}
helm.sh/chart: {{ include "dgraph.chart" . }}
{{ include "dgraph.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dgraph.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dgraph.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "dgraph.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "dgraph.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name (for the metrics image)
*/}}
{{- define "dgraph.image" -}}
{{- $registryName := .Values.image.registry -}}
{{- $repositoryName := .Values.image.repository -}}
{{- $tag := .Values.image.tag | toString -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 doesn't support it, so we need to implement this if-else logic.
Also, we can't use a single if because lazy evaluation is not an option
*/}}
{{- if .Values.global }}
    {{- if .Values.global.imageRegistry }}
        {{- printf "%s/%s:%s" .Values.global.imageRegistry $repositoryName $tag -}}
    {{- else -}}
        {{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
    {{- end -}}
{{- else -}}
    {{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- end -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "dgraph.imagePullSecrets" -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 doesn't support it, so we need to implement this if-else logic.
Also, we can't use a single if because lazy evaluation is not an option
*/}}
{{- if .Values.global }}
{{- if .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.global.imagePullSecrets }}
  - name: {{ . }}
{{- end }}
{{- else if .Values.image.pullSecrets }}
imagePullSecrets:
{{- range .Values.image.pullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end -}}
{{- else if .Values.image.pullSecrets }}
imagePullSecrets:
{{- range .Values.image.pullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Return the proper Storage Class
*/}}
{{- define "dgraph.storageClass" -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 does not support it, so we need to implement this if-else logic.
*/}}
{{- if .Values.global -}}
    {{- if .Values.global.storageClass -}}
        {{- if (eq "-" .Values.global.storageClass) -}}
            {{- printf "storageClassName: \"\"" -}}
        {{- else }}
            {{- printf "storageClassName: %s" .Values.global.storageClass -}}
        {{- end -}}
    {{- else -}}
        {{- if .Values.persistence.storageClass -}}
              {{- if (eq "-" .Values.persistence.storageClass) -}}
                  {{- printf "storageClassName: \"\"" -}}
              {{- else }}
                  {{- printf "storageClassName: %s" .Values.persistence.storageClass -}}
              {{- end -}}
        {{- end -}}
    {{- end -}}
{{- else -}}
    {{- if .Values.persistence.storageClass -}}
        {{- if (eq "-" .Values.persistence.storageClass) -}}
            {{- printf "storageClassName: \"\"" -}}
        {{- else }}
            {{- printf "storageClassName: %s" .Values.persistence.storageClass -}}
        {{- end -}}
    {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Helper function to determine CPU limit based on conditions
*/}}
{{- define "dgraph.zero.limits.cpu" -}}
{{- if (.Values.zero.resources.limits).cpu -}}
{{- .Values.zero.resources.limits.cpu -}}
{{- else if eq "small" (.Values.global.deploymentSize | lower | default "small") -}}
{{- .Values.zero.resources_small.limits.cpu -}}
{{- else if eq "large" (.Values.global.deploymentSize | lower) -}}
{{- .Values.zero.resources_large.limits.cpu -}}
{{- else -}}
{{- .Values.zero.resources_small.limits.cpu -}}
{{- end -}}
{{- end -}}

{{/*
Helper function to determine CPU limit based on conditions
*/}}
{{- define "dgraph.alpha.limits.cpu" -}}
{{- if (.Values.alpha.resources.limits).cpu -}}
{{- .Values.alpha.resources.limits.cpu -}}
{{- else if eq "small" (.Values.global.deploymentSize | lower | default "small") -}}
{{- .Values.alpha.resources_small.limits.cpu -}}
{{- else if eq "large" (.Values.global.deploymentSize | lower) -}}
{{- .Values.alpha.resources_large.limits.cpu -}}
{{- else -}}
{{- .Values.alpha.resources_small.limits.cpu -}}
{{- end -}}
{{- end -}}


{{/*
Helper function to determine Memory limit based on conditions
*/}}
{{- define "dgraph.zero.limits.memory" -}}
{{- if (.Values.zero.resources.limits).memory -}}
{{- .Values.zero.resources.limits.memory -}}
{{- else if eq "small" (.Values.global.deploymentSize | lower | default "small") -}}
{{- .Values.zero.resources_small.limits.memory -}}
{{- else if eq "large" (.Values.global.deploymentSize | lower) -}}
{{- .Values.zero.resources_large.limits.memory -}}
{{- else -}}
{{- .Values.zero.resources_small.limits.memory -}}
{{- end -}}
{{- end -}}

{{/*
Helper function to determine Memory limit based on conditions
*/}}
{{- define "dgraph.alpha.limits.memory" -}}
{{- if (.Values.alpha.resources.limits).memory -}}
{{- .Values.alpha.resources.limits.memory -}}
{{- else if eq "small" (.Values.global.deploymentSize | lower | default "small") -}}
{{- .Values.alpha.resources_small.limits.memory -}}
{{- else if eq "large" (.Values.global.deploymentSize | lower) -}}
{{- .Values.alpha.resources_large.limits.memory -}}
{{- else -}}
{{- .Values.alpha.resources_small.limits.memory -}}
{{- end -}}
{{- end -}}
