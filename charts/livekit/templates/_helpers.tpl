{{- define "livekit.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "livekit.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "livekit.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "livekit.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "livekit.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "livekit.selectorLabels" -}}
app.kubernetes.io/name: {{ include "livekit.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "livekit.portOffset" -}}
{{- .Values.livekit.portOffset | default 0 | int -}}
{{- end }}

{{- define "livekit.httpPort" -}}
{{- add (.Values.livekit.port | int) (include "livekit.portOffset" . | int) -}}
{{- end }}

{{- define "livekit.rtcTcpPort" -}}
{{- add (.Values.livekit.rtc.tcpPort | int) (include "livekit.portOffset" . | int) -}}
{{- end }}

{{- define "livekit.rtcUdpPort" -}}
{{- add (.Values.livekit.rtc.udpPort | int) (include "livekit.portOffset" . | int) -}}
{{- end }}

{{- define "livekit.prometheusPort" -}}
{{- add (.Values.livekit.prometheus.port | int) (include "livekit.portOffset" . | int) -}}
{{- end }}

{{- define "livekit.turnTlsPort" -}}
{{- add (.Values.livekit.turn.tlsPort | int) (include "livekit.portOffset" . | int) -}}
{{- end }}

{{- define "livekit.turnUdpPort" -}}
{{- add (.Values.livekit.turn.udpPort | int) (include "livekit.portOffset" . | int) -}}
{{- end }}
