{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "dgraph.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 24 -}}
{{- end -}}
{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "dgraph.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "dgraph.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

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
Create a default fully qualified data name.
*/}}
{{- define "dgraph.zero.fullname" -}}
{{ template "dgraph.fullname" . }}-{{ .Values.zero.name }}
{{- end -}}

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
Create a default fully qualified alpha name.
*/}}
{{- define "dgraph.alpha.fullname" -}}
{{ template "dgraph.fullname" . }}-{{ .Values.alpha.name }}
{{- end -}}


{{/*
Create a default fully qualified ratel name.
*/}}
{{- define "dgraph.ratel.fullname" -}}
{{ template "dgraph.fullname" . }}-{{ .Values.ratel.name }}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "dgraph-ha.labels" -}}
app: {{ template "dgraph.name" . }}
chart: {{ template "dgraph.chart" . }}
release: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}


{{- define "multi_zeros" -}}
  {{- $zeroFullName := include "dgraph.zero.fullname" . -}}
  {{- $max := int .Values.zero.replicaCount -}}
  {{- $safeVersion := include "dgraph.version" . -}}
  {{- /* Reset $max to 1 if multiple zeros not supported by dgraph version */}}
  {{- if semverCompare "< 1.2.3 || 20.03.0" $safeVersion -}}
     {{- $max = 1 -}}
  {{- end -}}

  {{- /* Append domain suffix if domain is used */}}
  {{- $domainSuffix := "" -}}
  {{- if .Values.global.domain -}}
  {{- $domainSuffix = printf ".%s" .Values.global.domain -}}
  {{- end -}}

  {{- /* Create comma-separated list of zeros */}}
  {{- range $idx := until $max }}
    {{- printf "%s-%d.%s-headless.${POD_NAMESPACE}.svc%s:5080" $zeroFullName $idx $zeroFullName $domainSuffix -}}
    {{- if ne $idx (sub $max 1) -}}
      {{- print "," -}}
    {{- end -}}
  {{ end }}
{{- end -}}

{{/*
Create a semVer/calVer version from image.tag so that it can be safely use in
version comparisions used to toggle features or behavior.
*/}}
{{- define "dgraph.version" -}}
{{- $safeVersion := .Values.image.tag -}}
{{- if (eq $safeVersion "shuri") -}}
  {{- $safeVersion = "v20.07.1" -}}
{{- else if  (regexMatch "^[^v].*" $safeVersion) -}}
  {{- $safeVersion = "v50.0.0" -}}
{{- end -}}
{{- printf "%s" $safeVersion -}}
{{- end -}}

{{- /* Generate domain name for first zero in cluster */}}
{{- define "peer_zero" -}}
  {{- $zeroFullName := include "dgraph.zero.fullname" . -}}

  {{- /* Append domain suffix if domain is used */}}
  {{- $domainSuffix := "" -}}
  {{- if .Values.global.domain -}}
  {{- $domainSuffix = printf ".%s" .Values.global.domain -}}
  {{- end -}}

  {{- printf "%s-%d.%s-headless.${POD_NAMESPACE}.svc%s:5080" $zeroFullName 0 $zeroFullName $domainSuffix -}}
{{- end -}}
{{- /* Superflag (v21.03.0) support and legacy flags */}}
{{- define "raft_index_flag" -}}
  {{- $safeVersion := include "dgraph.version" . -}}
  {{- if semverCompare ">= 21.03.0" $safeVersion -}}
    {{- printf "--raft idx=" -}}
  {{- else -}}
    {{- printf "--idx " -}}
  {{- end -}}
{{- end -}}