{{/*
Expand the name of the chart.
*/}}
{{- define "conformer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "conformer.fullname" -}}
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
Common labels
*/}}
{{- define "conformer.labels" -}}
helm.sh/chart: {{ include "conformer.name" . }}-{{ .Chart.Version | replace "+" "_" }}
{{ include "conformer.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "conformer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "conformer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Registry API component labels
*/}}
{{- define "conformer.registryLabels" -}}
{{ include "conformer.labels" . }}
app.kubernetes.io/component: registry-api
{{- end }}

{{/*
Registry API selector labels
*/}}
{{- define "conformer.registrySelectorLabels" -}}
{{ include "conformer.selectorLabels" . }}
app.kubernetes.io/component: registry-api
{{- end }}

{{/*
MinIO internal service name (from Bitnami subchart)
*/}}
{{- define "conformer.minioEndpoint" -}}
{{- printf "%s-minio:9000" .Release.Name }}
{{- end }}

{{/*
Keycloak issuer URL
*/}}
{{- define "conformer.keycloakIssuer" -}}
{{- printf "https://auth.%s/realms/compliance" .Values.domain }}
{{- end }}

{{/*
Keycloak JWKS URL
*/}}
{{- define "conformer.keycloakJWKS" -}}
{{- printf "https://auth.%s/realms/compliance/protocol/openid-connect/certs" .Values.domain }}
{{- end }}
