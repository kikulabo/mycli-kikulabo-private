// Package tracing provides OTel TracerProvider initialization and helpers.
package tracing

import (
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"
)

// Tracer returns the global Tracer for mycli.
func Tracer() trace.Tracer {
	return otel.Tracer("mycli")
}
