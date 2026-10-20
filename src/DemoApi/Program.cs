using System.Diagnostics;
using System.Diagnostics.Metrics;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);

var serviceName = builder.Configuration["OTEL_SERVICE_NAME"] ?? "demo-api";

builder.Services
    .AddOpenTelemetry()
    .ConfigureResource(resource => resource.AddService(serviceName))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation(options => options.Filter = context => context.Request.Path != "/health")
        .AddHttpClientInstrumentation()
        .AddSource(DemoTelemetry.ActivitySourceName))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddMeter(DemoTelemetry.MeterName))
    .UseOtlpExporter();

builder.Logging.AddOpenTelemetry(options =>
{
    options.IncludeFormattedMessage = true;
    options.IncludeScopes = true;
});

var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

// Constant fast response: the baseline for latency comparisons.
app.MapGet("/api/fast", () => Results.Ok(new { message = "fast" }));

// Latency follows a log-normal distribution, like many real services.
// Optional "ms" sets the median in milliseconds.
app.MapGet("/api/slow", async (int? ms, ILogger<Program> logger) =>
{
    using var activity = DemoTelemetry.Source.StartActivity("simulate-work");
    var median = Math.Clamp(ms ?? 150, 1, 5000);
    var delay = (int)Math.Min(median * Math.Exp(DemoTelemetry.NextGaussian() * 0.5), 10_000);
    activity?.SetTag("work.delay_ms", delay);
    await Task.Delay(delay);
    logger.LogInformation("Simulated work finished in {DelayMs} ms", delay);
    return Results.Ok(new { delayMs = delay });
});

// Fails with HTTP 500 for the given fraction of requests (default 10%).
app.MapGet("/api/flaky", (double? rate, ILogger<Program> logger) =>
{
    var failureRate = Math.Clamp(rate ?? 0.1, 0, 1);
    if (Random.Shared.NextDouble() < failureRate)
    {
        DemoTelemetry.Failures.Add(1);
        logger.LogError("Simulated failure at rate {FailureRate}", failureRate);
        return Results.Problem("Simulated failure", statusCode: StatusCodes.Status500InternalServerError);
    }

    return Results.Ok(new { message = "ok" });
});

// Burns CPU so saturation shows up in runtime metrics and profiles.
app.MapGet("/api/cpu", (int? iterations) =>
{
    using var activity = DemoTelemetry.Source.StartActivity("burn-cpu");
    var count = Math.Clamp(iterations ?? 200_000, 1, 5_000_000);
    activity?.SetTag("work.iterations", count);
    var hash = 17;
    for (var i = 0; i < count; i++)
    {
        hash = HashCode.Combine(hash, i);
    }

    return Results.Ok(new { hash });
});

app.Run();

internal static class DemoTelemetry
{
    public const string ActivitySourceName = "DemoApi";
    public const string MeterName = "DemoApi";

    public static readonly ActivitySource Source = new(ActivitySourceName);
    private static readonly Meter Meter = new(MeterName);
    public static readonly Counter<long> Failures = Meter.CreateCounter<long>(
        "demo.simulated_failures", description: "Number of simulated failures returned by /api/flaky");

    // Box-Muller transform: standard normal sample.
    public static double NextGaussian()
    {
        var u1 = 1.0 - Random.Shared.NextDouble();
        var u2 = Random.Shared.NextDouble();
        return Math.Sqrt(-2.0 * Math.Log(u1)) * Math.Cos(2.0 * Math.PI * u2);
    }
}

public partial class Program;
