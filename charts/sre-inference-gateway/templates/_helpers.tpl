{{- define "gateway.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "gateway.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "gateway.labels" -}}
{{ include "gateway.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "gateway.image" -}}
{{- $repo := required "image.repository is required (Docker Hub repository)" .Values.image.repository -}}
{{- $tag := required "image.tag is required (a git SHA)" .Values.image.tag -}}
{{- if not (kindIs "string" $tag) -}}
{{- fail "image.tag must be quoted: an all-digit SHA is otherwise read as a number and changed" -}}
{{- end -}}
{{- if eq $tag "latest" -}}
{{- fail "image.tag must be a git SHA, not latest" -}}
{{- end -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
