{{/* All global functions and ones related to third parties */}}

{{/*
Define if it's a release update*/}}
{{- define "sisense.update" -}}
{{- if eq .Release.Revision 1 -}}
false
{{- else -}}
true
{{- end -}}
{{- end -}}
