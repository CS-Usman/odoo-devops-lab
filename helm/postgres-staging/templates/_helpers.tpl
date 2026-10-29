{{- define "postgres-staging.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "postgres-staging.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "postgres-staging.name" . -}}
{{- end -}}
{{- end -}}

{{- define "postgres-staging.labels" -}}
app.kubernetes.io/name: {{ include "postgres-staging.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
