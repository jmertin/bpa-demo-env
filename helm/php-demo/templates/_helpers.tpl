{{/*
Expand the name of the chart.
*/}}
{{- define "php-demo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "php-demo.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Chart label value.
*/}}
{{- define "php-demo.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "php-demo.labels" -}}
helm.sh/chart: {{ include "php-demo.chart" . }}
{{ include "php-demo.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "php-demo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "php-demo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the MariaDB credentials secret.
*/}}
{{- define "php-demo.secretName" -}}
{{- printf "%s-db-secret" (include "php-demo.fullname" .) }}
{{- end }}

{{/*
Name of the nginx + php-fpm ConfigMap.
*/}}
{{- define "php-demo.configmapName" -}}
{{- printf "%s-config" (include "php-demo.fullname" .) }}
{{- end }}

{{/*
Name of the MariaDB PersistentVolumeClaim.
*/}}
{{- define "php-demo.pvcName" -}}
{{- printf "%s-mariadb-data" (include "php-demo.fullname" .) }}
{{- end }}

{{/*
Name of the registry image-pull secret.
*/}}
{{- define "php-demo.registrySecretName" -}}
{{- printf "%s-registry-pull" (include "php-demo.fullname" .) }}
{{- end }}

{{/*
Build the .dockerconfigjson payload for the registry pull secret.
The auth field is base64(<username>:<password>) as required by the Docker
credential format.
*/}}
{{- define "php-demo.dockerconfigjson" -}}
{{- with .Values.imageCredentials -}}
{{- printf "{\"auths\":{\"%s\":{\"auth\":\"%s\"}}}" .registry (printf "%s:%s" .username .password | b64enc) -}}
{{- end -}}
{{- end -}}
