package tracing

import (
	"context"
	"errors"
	"fmt"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/exporters/stdout/stdouttrace"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.27.0"
)

// Init initializes the global TracerProvider based on MYCLI_TRACES_EXPORTER.
// Returns a shutdown function that must be called before process exit.
func Init(ctx context.Context) (func(context.Context) error, error) {
	exporterName := os.Getenv("MYCLI_TRACES_EXPORTER")

	switch exporterName {
	case "", "none":
		return func(context.Context) error { return nil }, nil

	case "stdout":
		exp, err := stdouttrace.New(stdouttrace.WithWriter(os.Stderr))
		if err != nil {
			return nil, fmt.Errorf("stdouttrace: %w", err)
		}
		return setupProvider(ctx, exp), nil

	case "otlp":
		endpoint := os.Getenv("MYCLI_OTLP_ENDPOINT")
		if endpoint == "" {
			return nil, errors.New("MYCLI_OTLP_ENDPOINT is required when MYCLI_TRACES_EXPORTER=otlp")
		}
		exp, err := otlptracehttp.New(ctx, otlptracehttp.WithEndpointURL(endpoint))
		if err != nil {
			return nil, fmt.Errorf("otlptracehttp: %w", err)
		}
		return setupProvider(ctx, exp), nil

	default:
		return nil, fmt.Errorf("unknown MYCLI_TRACES_EXPORTER: %q (valid: none, stdout, otlp)", exporterName)
	}
}

func setupProvider(ctx context.Context, exp sdktrace.SpanExporter) func(context.Context) error {
	res, _ := resource.New(ctx,
		resource.WithAttributes(semconv.ServiceNameKey.String("mycli")),
	)
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exp, sdktrace.WithBlocking()),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	return tp.Shutdown
}
