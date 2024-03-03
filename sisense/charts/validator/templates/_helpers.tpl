{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "validator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "validator.fullname" -}}
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
{{- define "validator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create Sisense version from chart version
*/}}
{{- define "validator.sisense.version" -}}
{{- $sisenseVersion := split "." .Chart.Version -}}
{{- printf "%s.%s.%s" $sisenseVersion._0 $sisenseVersion._1 $sisenseVersion._2 | trimSuffix "." -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "validator.labels" -}}
app.kubernetes.io/name: {{ template "validator.name" . }}
helm.sh/chart: {{ include "validator.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
sisense-version: {{ include "validator.sisense.version" . }}
{{- if .Values.labels -}}
{{- range $key,$value := .Values.labels }}
{{ $key }}: {{ $value }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "validator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "validator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create template for check-validator init-container.
*/}}
{{- define "validator.init-container.check-validator" -}}
image: "{{ .Values.global.imageRegistry }}/utilsbox:stable"
command:
  - sh
  - -c
  - |
    namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace);
    certificate_path='/var/run/secrets/kubernetes.io/serviceaccount/ca.crt';

    service_url="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}";
    request_url="${service_url}/apis/batch/v1/namespaces/${namespace}/jobs/validator";

    token=$(cat '/var/run/secrets/kubernetes.io/serviceaccount/token');
    token_header="Authorization: Bearer ${token}";

    while : ; do
      echo 'waiting for validator';
      response=$(curl -s -H "${token_header}" --cacert "${certificate_path}" "${request_url}" || echo '');
      response_reason=$(echo "${response}" | jq -r ".reason");

      if [ ${response_reason} == 'NotFound' ]; then
        echo 'validator job not found ... skipping';
        break;
      fi;

      is_succeeded=$(echo "${response}" | jq ".status.succeeded");
      if [ "${is_succeeded}" == '1' ]; then
        echo 'validator is succeeded';
        break;
      fi;

      sleep 0.5;
    done;
{{- end -}}

{{- define "validator.old.system.alias" -}}
  {{- $configmap := (lookup "v1" "ConfigMap" .Release.Namespace "global-configuration") }}
  {{- if $configmap -}}
    {{- $oldalias := get $configmap.data "SYSTEM_ALIAS" }}
    {{- printf "%s" $oldalias -}}
  {{- else -}}
    {{- printf "" -}}
  {{- end }}
{{- end -}}
